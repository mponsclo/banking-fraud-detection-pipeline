# CaixaBank Data AI Hackathon

[![Python 3.10](https://img.shields.io/badge/python-3.10-blue.svg)](https://www.python.org/downloads/)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![dbt](https://img.shields.io/badge/dbt-BigQuery-orange.svg)](https://docs.getdbt.com/)
[![FastAPI](https://img.shields.io/badge/serving-FastAPI-009688.svg)](https://fastapi.tiangolo.com/)
[![GCP](https://img.shields.io/badge/infra-GCP%20%2F%20Terraform-4285F4.svg)](https://cloud.google.com/)

End-to-end banking data science pipeline: fraud detection with **LightGBM + Focal Loss** (BA=0.97), expense forecasting with **direct multi-step regression** (R2=0.76), and an AI-powered report agent with **LangChain**. Data engineering with **dbt on BigQuery**, served via **FastAPI on Cloud Run**, infrastructure managed with **Terraform**, and CI/CD with **GitHub Actions + SOPS/KMS**.

**Results:** 5/5 tasks complete, 9/9 tests pass.

| Task | Score Metric | Result |
|------|-------------|--------|
| 1. Data Queries | Exact match | 4/4 correct |
| 2. Data Functions | Pytest | 6/6 pass |
| 3. Fraud Detection | Balanced Accuracy | BA=0.97, AUPRC=0.61, F1=0.60 |
| 4. Expense Forecast | R2 Score | R2=0.76 (near theoretical ceiling) |
| 5. AI Agent | Pytest | 3/3 pass |

---

## Key Features

- **Reproducible data pipeline** -- dbt models on BigQuery transform 13M transactions through landing, logic, and presentation layers with schema tests
- **Production fraud detection** -- LightGBM with Focal Loss, 60+ features (velocity, behavioral, error flags, geographic anomaly), out-of-fold target encoding, leakage detection via ablation
- **Expense forecasting** -- Global LightGBM with direct multi-step forecasting (3 horizon models), walk-forward validated across 8 folds
- **AI agent** -- Hybrid LLM + deterministic pipeline with 3-layer strategy: Vertex AI Gemini (scaffold), Ollama (local), regex fallback (default)
- **REST API** -- FastAPI with fraud, forecast, and report endpoints, deployed on Cloud Run (scale 0-3)
- **Infrastructure as Code** -- Terraform-managed GCP resources (BigQuery, Cloud Run, Artifact Registry, KMS, IAM, Workload Identity Federation)
- **CI/CD** -- GitHub Actions for Terraform validate/plan/apply and Docker build+deploy, with SOPS-encrypted secrets
- **No service account keys** -- Workload Identity Federation for keyless GitHub → GCP authentication

---

## Prerequisites

| Requirement | Version | Notes |
|-------------|---------|-------|
| Python | 3.10+ | Runtime |
| pip | latest | Package management |
| GCP account | -- | BigQuery, Cloud Run access |
| gcloud CLI | latest | GCP authentication |
| Terraform | 1.7+ | Infrastructure management |
| Docker | 20+ | Optional, for containerized deployment |

## Quick Start

```bash
# Clone and set up environment
git clone https://github.com/mponsclo/caixabank-data-ai-hackathon.git
cd caixabank-data-ai-hackathon
python -m venv venv && source venv/bin/activate

# Install dependencies and build data pipeline
make install
gcloud auth application-default login
make load-data      # one-time: upload large CSVs to GCS + BigQuery
make dbt-build      # seed + run + test on BigQuery

# Train and export models
make export-models  # serialize to outputs/models/

# Run API locally
make serve          # http://localhost:8080/docs

# Run tests
make test           # 9/9 should pass
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Infrastructure (Terraform)                                       │
│  GCP Project → BigQuery (3 datasets) → Cloud Run → Artifact Reg │
│  KMS/SOPS → IAM → Workload Identity Federation                  │
├─────────────────────────────────────────────────────────────────┤
│ Data Layer (dbt + BigQuery)                                      │
│  CSV/GCS → landing (seeds+tables) → logic (views) → presentation│
│  mart_fraud_features (60+ cols) │ mart_client_monthly_expenses   │
├─────────────────────────────────────────────────────────────────┤
│ ML Layer (LightGBM)                                              │
│  Fraud: Focal Loss + Target Encoding → BA=0.97, AUPRC=0.61      │
│  Forecast: Direct 3-step → R2=0.76 (near ceiling)               │
├─────────────────────────────────────────────────────────────────┤
│ Serving Layer (FastAPI on Cloud Run)                              │
│  /predict/fraud │ /predict/forecast │ /report/generate │ /health │
│  Agent: Vertex AI (scaffold) → Ollama (local) → Regex (default)  │
├─────────────────────────────────────────────────────────────────┤
│ CI/CD (GitHub Actions)                                           │
│  terraform-validate → terraform-plan → terraform-apply           │
│  docker-build → push Artifact Registry → deploy Cloud Run        │
└─────────────────────────────────────────────────────────────────┘
```

---

## API Reference

```bash
# Health check
curl http://localhost:8080/health

# Fraud prediction
curl -X POST http://localhost:8080/predict/fraud \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "123", "amount": -150.0, "use_chip": "Online Transaction", "mcc": 5411, "merchant_id": 100, "is_online": 1, "txn_hour": 3, "credit_limit": 5000}'

# Expense forecast
curl -X POST http://localhost:8080/predict/forecast \
  -H "Content-Type: application/json" \
  -d '{"client_id": 0}'

# Report generation
curl -X POST http://localhost:8080/report/generate \
  -H "Content-Type: application/json" \
  -d '{"client_id": 0, "prompt": "Create a report for the fourth month of 2017"}'
```

---

## Infrastructure

### Terraform (Two-Phase)

| Phase | Scope | How |
|-------|-------|-----|
| **Bootstrap** | GCP project, APIs, GCS state bucket, KMS key, service accounts, Workload Identity Federation | `cd terraform/bootstrap && terraform apply` (local, one-time) |
| **Main config** | BigQuery datasets, Cloud Run service, Artifact Registry, IAM bindings | GitHub Actions on merge to `main` |

### CI/CD Workflows

| Workflow | Trigger | Gate |
|----------|---------|------|
| `terraform-validate` | PR to `terraform/**` | None (no GCP auth) |
| `terraform-plan` | PR to `terraform/**` | Plan posted as PR comment |
| `terraform-apply` | Push to `main` | `production` environment (manual approval) |
| `docker-build-deploy` | Push to `main` (app/src changes) | `production` environment (manual approval) |

### Secrets Management

- **SOPS + GCP KMS**: `terraform.tfvars.enc` committed encrypted, decrypted in CI via Workload Identity Federation
- **No service account keys**: GitHub Actions authenticates via OIDC tokens → WIF → SA impersonation
- **CODEOWNERS**: Terraform and workflow changes require explicit review

---

## Production Roadmap

The project implements IaC, CI/CD, typed APIs, and data quality testing. The following items would complete the production story:

| Gap | Current State | Production Target |
|-----|--------------|-------------------|
| **Data ingestion** | One-time CSV load to GCS | Pub/Sub + Cloud Functions for streaming transaction ingestion |
| **Feature store** | Features computed in dbt mart | Vertex AI Feature Store for real-time fraud scoring |
| **Model registry** | pkl files baked into Docker image | Vertex AI Model Registry with versioning + A/B deployment |
| **Model monitoring** | None | Log predictions to BQ `predictions_log`, scheduled drift detection (PSI) |
| **Integration tests** | 9 pytest tests (local only) | API contract tests in CI + BigQuery data quality checks |
| **Alerting** | Budget alerts only | Cloud Monitoring uptime checks on `/health`, error rate alerts, Slack integration |
| **LLM agent** | Vertex AI scaffold (inactive) + regex default | Activate Vertex AI Gemini via `AGENT_LLM_BACKEND=vertex` |
| **Batch scoring** | On-demand scripts | Cloud Scheduler + Cloud Run Jobs for daily fraud scoring |

---

## Development

### Training models

```bash
make train          # Train fraud + forecast, print metrics
make export-models  # Serialize for API serving
```

### Testing

```bash
make test           # 9 tests: statistics (6) + agent (3)
```

### Docker

```bash
make docker-build       # Build image
make docker-run         # Run API container (port 8080)
make docker-compose-up  # Start services
make docker-compose-down
```

---

## Project Structure

```
├── terraform/                  # Infrastructure as Code
│   ├── bootstrap/              # One-time: project, KMS, SAs, WIF
│   └── modules/                # iam, kms, bigquery, cloud_run, artifact_registry, workload_identity
├── .github/workflows/          # CI/CD: validate, plan, apply, deploy
├── app/                        # FastAPI serving layer
│   ├── routers/                # health, fraud, forecast, agent
│   └── model_loader.py         # Lifespan model loading
├── dbt/                        # Data pipeline (BigQuery)
│   ├── models/                 # staging → intermediate → marts
│   ├── seeds/                  # Small reference data
│   └── macros/                 # BigQuery schema routing
├── src/                        # ML models + agent
│   ├── models/                 # train_model.py, predict_model.py
│   └── agent/                  # LLM date extraction + PDF generation
├── scripts/                    # Data loading + model export
├── tests/                      # Hackathon test suite
└── experiments.md              # Full experiment log
```

---

## Key Technical Decisions

1. **dbt + BigQuery over pandas** — SQL-based feature engineering with 60+ window functions is more reproducible and testable than pandas chains. The `generate_schema_name` macro maps dbt models to BigQuery datasets cleanly.

2. **Focal loss over class weights** — For 0.15% fraud rate, focal loss (gamma=2.0) outperformed scale_pos_weight tuning by focusing gradient updates on hard-to-classify examples.

3. **Direct over recursive forecasting** — Three separate horizon models avoid error propagation. Since autocorrelation ≈ 0, there's no temporal structure for recursive to exploit.

4. **3-layer LLM strategy** — Vertex AI Gemini scaffold (production-ready but inactive to avoid costs), Ollama (local development), regex fallback (deterministic default). Controlled by a single env var.

5. **Workload Identity Federation over SA keys** — GitHub Actions authenticates via OIDC tokens, eliminating key rotation and storage concerns.

6. **SOPS + KMS over GitHub Secrets only** — Encrypted secrets committed to repo, version-controlled, decryptable only by authorized identities.

---

## Experiment Tracking

Full experiment logs with metrics, ablation studies, and root cause analysis in [experiments.md](experiments.md) — 11 experiments total across fraud detection and expense forecasting.

---

## License

[MIT](LICENSE)
