# Terraform Modules

Reusable building blocks composed by [`terraform/main.tf`](../main.tf). Each module
is scoped to one GCP concern and exposes a minimal interface.

The root config applies only once [`terraform/bootstrap/`](../bootstrap/) has run —
bootstrap creates the GCP project, enables APIs, provisions service accounts, and
sets up the KMS keyring. Modules here reference those resources as data sources
rather than owning them, to keep the chicken-and-egg case clean.

## Module map

| Module | Purpose | Key inputs | Key outputs |
|---|---|---|---|
| [`iam/`](iam/) | Reads the three bootstrap-owned service accounts (Cloud Run, GitHub Actions, pipeline) as data sources. | `project_id` | `cloud_run_sa_email`, `github_actions_sa_email`, `pipeline_sa_email` |
| [`kms/`](kms/) | References the SOPS crypto key and grants collaborators `encrypter/decrypter` for `terraform.tfvars.enc`. | `project_id`, `collaborator_emails` | `key_id` (for `.sops.yaml`) |
| [`artifact_registry/`](artifact_registry/) | Docker repo `caixabank-ai` for the API image. | `project_id`, `region` | `repository_url`, `repository_id` |
| [`bigquery/`](bigquery/) | Creates the three-layer warehouse: `landing`, `logic`, `presentation`. | `project_id`, `region` | `dataset_ids` (map) |
| [`cloud_run/`](cloud_run/) | Deploys the FastAPI serving container, 0–3 instances, public access. | `project_id`, `region`, `cloud_run_sa_email`, `image` | `service_url`, `service_name` |
| [`pubsub/`](pubsub/) | `transactions-ingestion` topic + DLQ for the streaming pipeline. | `project_id`, `region` | `topic_name`, `topic_id`, `dlq_topic_name`, `dlq_topic_id` |
| [`cloud_functions/`](cloud_functions/) | Producer (HTTP, GCS → Pub/Sub) + consumer (EventArc, Pub/Sub → BigQuery) + daily Cloud Scheduler trigger. | `project_id`, `region`, `pipeline_sa_email`, `pubsub_topic_name`, `source_bucket_name`, `source_data_bucket` | `producer_url`, `consumer_url`, `scheduler_job_name` |
| [`workload_identity/`](workload_identity/) | References the WIF pool + GitHub provider so CI can impersonate `github-actions-sa` without stored keys. | `project_id` | `provider_name` (→ GitHub secret `WIF_PROVIDER`), `pool_name` |

## Dependency flow

```
iam ──► cloud_run_sa_email ──► cloud_run
    └─► pipeline_sa_email ──► cloud_functions
pubsub ──► topic_name ──────► cloud_functions
```

All other modules are standalone and only consume `project_id` / `region`.

## Conventions

- Every module is `main.tf` + `variables.tf` + `outputs.tf`. No submodules.
- Resources that must pre-exist (service accounts, KMS key, WIF pool) are read
  via `data` blocks, never recreated here.
- Inputs and outputs carry `description` fields so `terraform-docs` renders
  cleanly if wired in later.

See [`docs/7-infrastructure.md`](../../docs/7-infrastructure.md) for the end-to-end
architecture, bootstrap sequence, and SOPS/KMS secret flow.
