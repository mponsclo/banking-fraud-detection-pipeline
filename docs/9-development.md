# Development & CI/CD

Python dev toolchain and non-Terraform GitHub Actions workflows. Complements [7-infrastructure.md](7-infrastructure.md), which covers the Terraform side.

## Why This Layer Exists

A portfolio project lives or dies on its ability to be set up, reviewed, and redeployed months after it was written. This layer is the glue that makes that possible: a single `make install` to bootstrap dependencies, a single `ruff` config that governs every Python file, pre-commit hooks that refuse malformed commits, a `Dockerfile` that reproduces the runtime, and five GitHub Actions workflows that lint, plan, and deploy without a human in the loop.

Three design decisions shape the layer:

- **One source of truth per concern.** Ruff config lives in [`pyproject.toml`](../pyproject.toml), pre-commit hooks in [`.pre-commit-config.yaml`](../.pre-commit-config.yaml), runtime deps in [`requirements.txt`](../requirements.txt), system deps in the [`Dockerfile`](../Dockerfile). No duplicated rules.
- **Every command has a Makefile target.** Developers never need to remember a flag combination. CI/CD calls the same tools locally available via `make lint`, `make test`, `make docker-build`.
- **CI enforces what pre-commit enforces.** `lint.yml` runs the same `ruff check` and `ruff format --check` that the pre-commit hook runs, so bypassing the hook locally still fails in PR.

## Makefile Reference

Full target catalog in [`Makefile`](../Makefile). Run `make help` for the live list.

### Install

| Target | Action |
|--------|--------|
| `install` | `pip install -r requirements.txt` |

### Data Pipeline (dbt + BigQuery)

| Target | Action |
|--------|--------|
| `dbt-build` | Full pipeline: seed + run + test |
| `dbt-seed` | Load seed CSVs into BigQuery |
| `dbt-run` | Run models only |
| `dbt-test` | Run schema + data tests |
| `dbt-docs` | Generate + serve dbt docs at http://localhost:8081 |
| `load-data` | One-time upload of large CSVs to GCS + BigQuery via `scripts/load_raw_data.sh` |

### ML Models

| Target | Action |
|--------|--------|
| `train` | Train fraud + forecast models, print metrics |
| `export-models` | Serialize trained models to `outputs/models/` for API serving |

### API

| Target | Action |
|--------|--------|
| `serve` | `uvicorn app.main:app --host 0.0.0.0 --port 8080 --reload` |

### Docker

| Target | Action |
|--------|--------|
| `docker-build` | Build `caixabank-ai-api` image |
| `docker-run` | Run container, map port 8080 |
| `docker-compose-up` | `docker compose up -d` |
| `docker-compose-down` | Stop compose services |

### Testing

| Target | Action |
|--------|--------|
| `test` | `pytest tests/ -v` (runs all 9 hackathon tests) |

### Code Quality

| Target | Action |
|--------|--------|
| `lint` | `ruff check .` + `ruff format --check .` (read-only) |
| `format` | `ruff check --fix .` + `ruff format .` (auto-fix) |

### Ingestion Pipeline

| Target | Action |
|--------|--------|
| `proto-compile` | Compile `transaction.proto` and copy outputs into function directories |
| `trigger-ingestion` | Manually POST to the producer function URL |

`trigger-ingestion` is the only non-obvious target: it reads the producer URL from Terraform state via a subshell (`terraform output -raw producer_function_url`) and authenticates with `gcloud auth print-identity-token`. It only works after `terraform apply` has run.

### Cleanup

| Target | Action |
|--------|--------|
| `clean` | Remove `dbt/target`, `dbt/logs`, `dbt/dbt_packages`, `__pycache__`, `*.pyc` |

## Code Quality — Ruff

Ruff is configured in [`pyproject.toml`](../pyproject.toml):

```toml
[tool.ruff]
target-version = "py310"
line-length = 120
exclude = ["*_pb2.py", "*.ipynb", "myenv", ".venv"]

[tool.ruff.lint]
select = ["E", "F", "I", "UP"]
ignore = ["E501"]

[tool.ruff.lint.isort]
known-first-party = ["src", "app"]

[tool.ruff.format]
quote-style = "double"
```

**Rule groups enabled:**
- `E` — pycodestyle errors
- `F` — pyflakes (unused imports, undefined names)
- `I` — isort (import ordering, with `src` and `app` marked first-party)
- `UP` — pyupgrade (modern Python 3.10 idioms)

**`E501` (line-too-long) is intentionally ignored** because the line length is already set to 120. The check would be redundant and noisy for long SQL strings and f-string log messages.

**Excludes:** Generated Protobuf (`*_pb2.py`) and exploratory notebooks (`*.ipynb`) are excluded from linting — they change by codegen or experimentation, not by hand.

Run locally:
```bash
make lint     # check only, exits non-zero on issues
make format   # auto-fix and format
```

## Pre-commit Hooks

Configured in [`.pre-commit-config.yaml`](../.pre-commit-config.yaml):

```yaml
repos:
  - repo: https://github.com/astral-sh/ruff-pre-commit
    rev: v0.15.10
    hooks:
      - id: ruff
        args: [--fix, --exit-non-zero-on-fix]
      - id: ruff-format
```

Two hooks run on every `git commit`:

1. **`ruff`** with `--fix --exit-non-zero-on-fix`: auto-fixes what it can, then **fails the commit** so you re-stage the fixed files. This prevents silent auto-fixes from landing unreviewed.
2. **`ruff-format`**: applies the canonical format.

Install once per clone:
```bash
pip install pre-commit
pre-commit install
```

After installation, no commit can introduce a lint error or format drift. The same checks run in [`lint.yml`](../.github/workflows/lint.yml), so bypassing the hook locally still fails in CI.

## Dockerfile

Full image definition in [`Dockerfile`](../Dockerfile) (25 lines).

**Base image:** `python:3.10-slim` — matches the `target-version` in `pyproject.toml` and the Cloud Run runtime.

**System dependencies (WeasyPrint):**

```dockerfile
RUN apt-get install -y --no-install-recommends \
    build-essential \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libgdk-pixbuf-2.0-0 \
    libffi-dev \
    libcairo2 \
    libglib2.0-0
```

WeasyPrint (used by the AI agent for PDF report generation — see [6-agent.md](6-agent.md)) wraps native libraries for font rendering, vector graphics, and image handling. These six packages are the minimum set required on Debian slim. Without them, `import weasyprint` succeeds but rendering fails at runtime with a GObject error.

**Build contents:**

```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src/ src/
COPY app/ app/
COPY outputs/models/ outputs/models/
EXPOSE 8080
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
```

Pre-trained models (`outputs/models/`) are baked into the image so the container starts cold with no BigQuery dependency. See [5-serving.md](5-serving.md) for the runtime lifespan pattern that loads them.

Build and run locally:
```bash
make docker-build
make docker-run
# → http://localhost:8080/docs
```

## GitHub Actions Workflows

Five workflows in [`.github/workflows/`](../.github/workflows/), covering two pipelines (Python/Docker + Terraform):

| Workflow | Trigger | Auth | Gate | Purpose |
|----------|---------|------|------|---------|
| [`lint.yml`](../.github/workflows/lint.yml) | PR + push to main (`**.py`, `pyproject.toml`) | None | — | `ruff check` + `ruff format --check` via `astral-sh/ruff-action@v3` |
| [`terraform-validate.yml`](../.github/workflows/terraform-validate.yml) | PR (`terraform/**`) | None | — | `fmt -check -recursive`, `init -backend=false`, `validate` |
| [`terraform-plan.yml`](../.github/workflows/terraform-plan.yml) | PR (`terraform/**`) | WIF + SOPS | — | Plan posted as PR comment |
| [`terraform-apply.yml`](../.github/workflows/terraform-apply.yml) | Push to main (`terraform/**`, `functions/**`, `proto/**`) | WIF + SOPS | `production` environment | `apply -auto-approve` |
| [`docker-build-deploy.yml`](../.github/workflows/docker-build-deploy.yml) | Push to main (`app/**`, `src/**`, `outputs/**`, `Dockerfile`, `requirements.txt`) | WIF | `production` environment | Build → push to Artifact Registry → deploy Cloud Run |

### Python pipeline

**`lint.yml`** is the only Python-facing workflow. It runs on every PR and every push to main that touches `.py` files or `pyproject.toml`. It uses the official [`astral-sh/ruff-action@v3`](https://github.com/astral-sh/ruff-action), which respects the repo's `pyproject.toml` config automatically — no config duplication in the workflow file. Two steps: `ruff check` and `ruff format --check`. Permissions are `contents: read` only.

### Terraform pipeline

Three chained workflows, all scoped to `terraform/**` PR paths:

1. **`terraform-validate.yml`** — fast, no GCP auth. Catches syntax errors and formatting issues in <30s.
2. **`terraform-plan.yml`** — authenticates via Workload Identity Federation, decrypts `terraform.tfvars.enc` with SOPS, runs `terraform plan`, and posts the plan as a PR comment for review. See [7-infrastructure.md](7-infrastructure.md) for the WIF + SOPS design.
3. **`terraform-apply.yml`** — triggered only on merge to main. Requires manual approval via the `production` GitHub Environment, then runs `terraform apply -auto-approve`.

### Docker deployment pipeline

**`docker-build-deploy.yml`** is the only deploy workflow for the API. Triggered on merge to main when runtime code changes (`app/`, `src/`, `outputs/`, `Dockerfile`, `requirements.txt`). Also gated by the `production` environment.

Four steps: WIF auth, `gcloud auth configure-docker`, `docker build && docker push` (tagged with `github.sha`), `gcloud run deploy`. The image goes to `europe-southwest1-docker.pkg.dev/<project>/caixabank-ai/api:<sha>` and the service is `caixabank-ai-api`.

### Branch protection via CODEOWNERS

[`.github/CODEOWNERS`](../.github/CODEOWNERS) gates review on the highest-risk paths:

```
terraform/              @mponsclo
terraform/bootstrap/    @mponsclo
.github/workflows/      @mponsclo
.sops.yaml              @mponsclo
```

Infra and CI/CD changes require explicit owner approval. Bootstrap is called out separately because it controls the GCP project root, SAs, KMS keys, and WIF — a misconfigured bootstrap can lock the whole project.

## Local Development Loop

A typical five-step flow:

```bash
# 1. One-time setup
make install
pip install pre-commit && pre-commit install

# 2. Make changes
#    (edit Python, dbt, or Terraform files)

# 3. Validate locally
make lint        # Ruff check + format check
make test        # pytest tests/ -v

# 4. Optional: integration-check the API
make docker-build && make docker-run
# → hit http://localhost:8080/docs

# 5. Commit
git commit -m "..."
# pre-commit auto-runs ruff check + format; fails the commit on any issue
```

For ingestion-specific changes, also run `make proto-compile` after editing `transaction.proto` — see [1-ingestion.md](1-ingestion.md).

For dbt model changes, `make dbt-build` hits BigQuery directly and requires `gcloud auth application-default login` — see [2-transformation.md](2-transformation.md).

## Cross-References

- [1-ingestion.md](1-ingestion.md) — `make proto-compile`, `make trigger-ingestion`
- [2-transformation.md](2-transformation.md) — `make dbt-build`, dbt commands
- [5-serving.md](5-serving.md) — Dockerfile runtime behavior, FastAPI lifespan model loading
- [6-agent.md](6-agent.md) — WeasyPrint rationale for the Docker system deps
- [7-infrastructure.md](7-infrastructure.md) — WIF token flow, SOPS/KMS secret management, Terraform module layout
