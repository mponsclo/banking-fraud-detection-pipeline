# CaixaBank Data AI Hackathon

> **Note:** This project was developed as part of a data science hackathon organized by NUWE in partnership with CaixaBank. The original datasets are not included in this repository as they may contain proprietary data. See [Data](#data) for details on the expected input format.

## Overview

End-to-end data science pipeline for banking transaction analysis: data engineering with **dbt + BigQuery**, fraud detection with **LightGBM + Focal Loss**, expense forecasting with **direct multi-step regression**, and an AI-powered report agent with **LangChain**. Infrastructure managed with **Terraform** on GCP, served via **FastAPI on Cloud Run**, CI/CD with **GitHub Actions + SOPS/KMS**.

**Results:** 5/5 tasks complete, 9/9 tests pass.

| Task | Score Metric | Result |
|------|-------------|--------|
| 1. Data Queries | Exact match | 4/4 correct |
| 2. Data Functions | Pytest | 6/6 pass |
| 3. Fraud Detection | Balanced Accuracy | BA=0.97, AUPRC=0.61, F1=0.60 |
| 4. Expense Forecast | R2 Score | R2=0.76 (near theoretical ceiling) |
| 5. AI Agent | Pytest | 3/3 pass |

---

## Architecture

### Data Pipeline (dbt + BigQuery)

Instead of ad-hoc pandas preprocessing, the data layer uses a proper **dbt pipeline** with BigQuery as the warehouse — staging, intermediate, and mart layers with SQL-based transformations and schema tests across 3 datasets (`landing`, `logic`, `presentation`).

![Data Model](data_model.png)

```
GCS/Seeds → [landing: staging views] → [logic: intermediate views] → [presentation: mart tables] → API
```

**Why dbt:** Reproducible transformations, testable SQL, self-documenting lineage. The `mart_fraud_features` table computes 60+ features (velocity, behavioral, error flags, geographic anomaly) entirely in SQL via window functions.

### Fraud Detection (Task 3)

**9 experiments** documented in [experiments.md](experiments.md), from a naive baseline (AUPRC≈0) to a production-grade model:

| Technique | Impact |
|-----------|--------|
| EDA-driven features (errors column, geographic anomaly) | AUPRC 0→0.43 |
| Out-of-fold target encoding (MCC, merchant_id) | AUPRC 0.43→0.49 |
| Focal loss (replaced scale_pos_weight) | AUPRC 0.49→0.57 |
| Card age, gap z-score, spending anomaly features | AUPRC 0.57→0.61 |

**Leakage caught:** Zip-based features inflated AUPRC to 0.89. Ablation study isolated the leak (client home zip computed from future data), features removed, honest metrics reported.

**Final model:** LightGBM + Focal Loss (gamma=2.0, alpha=0.25) + target encoding. Production operating point: 64% precision, 57% recall.

### Expense Forecast (Task 4)

Global LightGBM with **direct multi-step forecasting** (separate model per horizon h=1,2,3).

**Key finding:** 77% of variance is between-client (spending level), autocorrelation ≈ 0, no seasonality. R2=0.76 is near the theoretical ceiling (~0.80-0.84). Validated by testing 7 alternative approaches (blending, residual modeling, two-stage, EWMA) — all converge to ~0.76.

Walk-forward validated with 8 folds, reporting R2, MAE ($239), and RMSE ($314).

### AI Agent (Task 5)

Hybrid architecture: 3-layer LLM strategy (Vertex AI Gemini scaffold, Ollama for local dev, regex fallback as default) + **deterministic pipeline** for client validation, data analysis, and PDF generation.

Regex fallback ensures reliability. Handles ordinal months ("fourth month of 2017"), explicit ISO ranges, month names, and quarters.

### Infrastructure (Terraform + GCP)

Two-phase Terraform: bootstrap (project, KMS, SAs, WIF) + main config (BigQuery, Cloud Run, Artifact Registry). Workload Identity Federation for keyless GitHub → GCP auth. SOPS/KMS-encrypted secrets.

---

## Data

The datasets are **not included** in this repository. To reproduce the results, you would need:

- `data/raw/transactions_data.csv` — Credit card transactions dataset (2010s decade) with columns: transaction ID, client ID, card ID, amount, merchant, MCC code, timestamps, errors, etc.
- `data/raw/mcc_codes.json` — Merchant Category Code mappings (109 categories).
- `data/raw/train_fraud_labels.json` — Binary fraud labels for training the detection model.
- Client and card data were fetched from APIs (no longer available) and stored as `clients_data_api.csv` and `card_data_api.csv`.

---

## How to Run

```bash
# Setup
make install
gcloud auth application-default login

# Load data into BigQuery (one-time)
make load-data

# Build dbt pipeline
make dbt-build

# Export models for API serving
make export-models

# Run API locally
make serve        # http://localhost:8080/docs

# Run tests
make test         # 9/9 should pass
```

---

## Key Technical Decisions

1. **dbt + BigQuery over pandas for data prep** — SQL-based feature engineering is more maintainable and testable than pandas chains. Window functions for velocity/behavioral features are cleaner in SQL.

2. **Focal loss over class weights** — For 0.15% fraud rate, focal loss (gamma=2.0) outperformed scale_pos_weight tuning by focusing gradient updates on hard-to-classify examples.

3. **Direct over recursive forecasting** — Three separate horizon models avoid error propagation. Since autocorrelation ≈ 0, there's no temporal structure for recursive to exploit.

4. **3-layer LLM strategy** — Vertex AI Gemini scaffold (production-ready), Ollama (local dev), regex fallback (deterministic default). Controlled by `AGENT_LLM_BACKEND` env var.

5. **Workload Identity Federation** — No service account keys stored anywhere. GitHub Actions authenticates via OIDC tokens.

6. **Parameterized SQL everywhere** — `con.execute(query, [params])` instead of f-strings to prevent SQL injection.

---

## Repository Structure

```
├── terraform/                  # Infrastructure as Code (GCP)
│   ├── bootstrap/              # One-time: project, KMS, SAs, WIF
│   └── modules/                # iam, kms, bigquery, cloud_run, artifact_registry, workload_identity
├── .github/workflows/          # CI/CD: validate, plan, apply, deploy
├── app/                        # FastAPI serving layer
│   └── routers/                # health, fraud, forecast, agent
├── dbt/                        # dbt-BigQuery data pipeline
│   ├── models/
│   │   ├── staging/            # 4 views: stg_transactions, stg_users, stg_cards, stg_mcc_codes
│   │   ├── intermediate/       # 2 views: int_transactions_enriched, int_client_transactions
│   │   └── marts/              # 2 tables: mart_fraud_features, mart_client_monthly_expenses
│   ├── seeds/                  # mcc_codes.csv, users_data.csv, cards_data.csv
│   └── macros/                 # generate_schema_name (BigQuery dataset routing)
├── scripts/                    # Data loading + model export
├── src/                        # Hackathon ML code (local dev, DuckDB for tests)
│   ├── data/                   # Task 1 queries, Task 2 functions
│   ├── models/                 # Task 3 fraud model, Task 4 forecast model
│   └── agent/                  # Task 5 AI agent
├── predictions/                # JSON outputs for Tasks 1, 3, 4
├── tests/                      # Hackathon test suite
├── experiments.md              # Full experiment log (11 experiments)
└── reports/figures/            # Generated plots
```

## Experiment Tracking

Full experiment logs with metrics, ablation studies, and root cause analysis are in [experiments.md](experiments.md) — 11 experiments total across fraud detection and expense forecasting.

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
