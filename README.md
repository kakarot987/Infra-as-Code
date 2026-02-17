# 🏗️ Infra-as-Code Foundation — GCP

> **Template: The "Infra-as-Code" Foundation**
> Stack: **Terraform + GitHub Actions + Datadog** on Google Cloud Platform

---

## Overview

This template gives you a production-grade IaC foundation for GCP with:

- **VPC** — Custom-mode VPC with private subnets, Cloud NAT, and Private Service Access
- **GKE** — Private cluster (Standard or Autopilot) with Workload Identity, auto-repair, and auto-upgrade
- **Cloud SQL** — Private PostgreSQL with Query Insights, automated backups, and deletion protection in prod
- **Datadog** — CPU/memory/disk monitors + an infrastructure dashboard, all provisioned via Terraform
- **GitHub Actions** — `tf plan` on PRs with automated PR comments; `tf apply` to dev then prod with manual approval gate
- **Security** — TFLint + Checkov scans run before any plan reaches the cloud

---

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | ≥ 1.7.0 | IaC engine |
| gcloud CLI | latest | GCP authentication |
| tflint | latest | Terraform linting |
| checkov | ≥ 3.0 | Security scanning |

---

## Repository Structure

```
.
├── .github/workflows/
│   ├── tf-plan.yml          # Runs on Pull Request — lint, scan, plan, PR comment
│   └── tf-apply.yml         # Runs on Merge to Main — apply dev → prod (with gate)
├── terraform/
│   ├── modules/
│   │   ├── vpc/             # Custom VPC, subnets, NAT, Private Service Access
│   │   ├── gke/             # GKE Standard/Autopilot private cluster + node pools
│   │   └── cloudsql/        # PostgreSQL with private IP, backups, Query Insights
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── dev.tfvars   # Dev-specific variable values
│   │   │   └── backend.conf # GCS state bucket for dev
│   │   └── prod/
│   │       ├── prod.tfvars  # Prod-specific variable values
│   │       └── backend.conf # GCS state bucket for prod
│   ├── main.tf              # Provider config + module orchestration
│   ├── variables.tf         # All input variable declarations
│   └── monitoring.tf        # Datadog monitors + dashboard (Terraform-managed)
└── README.md
```

---

## Initial Setup

### 1. Create GCS Buckets for Terraform State

```bash
# Dev state bucket
gcloud storage buckets create gs://my-project-dev-tfstate \
  --project=my-project-dev \
  --location=US \
  --uniform-bucket-level-access

# Prod state bucket
gcloud storage buckets create gs://my-project-prod-tfstate \
  --project=my-project-prod \
  --location=US \
  --uniform-bucket-level-access

# Enable versioning for state file recovery
gcloud storage buckets update gs://my-project-dev-tfstate --versioning
gcloud storage buckets update gs://my-project-prod-tfstate --versioning
```

### 2. Enable Required GCP APIs

```bash
gcloud services enable \
  compute.googleapis.com \
  container.googleapis.com \
  sqladmin.googleapis.com \
  servicenetworking.googleapis.com \
  cloudresourcemanager.googleapis.com \
  iam.googleapis.com \
  --project=my-project-dev
```

### 3. Configure Workload Identity Federation (for GitHub Actions)

```bash
# Create the Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --project=my-project-dev \
  --location="global" \
  --display-name="GitHub Actions Pool"

# Create the OIDC Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --project=my-project-dev \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub OIDC Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --issuer-uri="https://token.actions.githubusercontent.com"

# Grant the Terraform service account permission to be impersonated
gcloud iam service-accounts add-iam-policy-binding \
  terraform@my-project-dev.iam.gserviceaccount.com \
  --project=my-project-dev \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/attribute.repository/YOUR_ORG/YOUR_REPO"
```

### 4. Set GitHub Secrets

Navigate to **Settings → Secrets and variables → Actions** in your repository:

| Secret | Value |
|--------|-------|
| `GCP_WIF_PROVIDER` | `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/github-pool/providers/github-provider` |
| `GCP_SA_EMAIL` | `terraform@my-project-dev.iam.gserviceaccount.com` |
| `GCP_WIF_PROVIDER_PROD` | Same format for prod project |
| `GCP_SA_EMAIL_PROD` | `terraform@my-project-prod.iam.gserviceaccount.com` |
| `TF_VAR_datadog_api_key` | Your Datadog API key |
| `TF_VAR_datadog_app_key` | Your Datadog App key |

### 5. Update Variable Files

Edit the following files to match your GCP project IDs:

- `terraform/environments/dev/dev.tfvars` — set `project_id`
- `terraform/environments/dev/backend.conf` — set `bucket`
- `terraform/environments/prod/prod.tfvars` — set `project_id`
- `terraform/environments/prod/backend.conf` — set `bucket`

---

## Local Development Workflow

```bash
cd terraform

# Initialize with dev backend
terraform init -backend-config=environments/dev/backend.conf

# Validate syntax
terraform validate

# Run linter
tflint --recursive

# Run security scan
checkov -d . --framework terraform

# Plan against dev
terraform plan -var-file=environments/dev/dev.tfvars

# Apply to dev
terraform apply -var-file=environments/dev/dev.tfvars
```

---

## CI/CD Pipeline

### Pull Request Flow (`tf-plan.yml`)

```
PR opened → TFLint → Checkov → terraform plan (dev) → Post plan to PR
```

The plan output is automatically posted as a PR comment so reviewers can see exactly what will change before approving.

### Merge to Main Flow (`tf-apply.yml`)

```
Merge to main → Apply to dev → [Manual approval gate] → Apply to prod
```

The prod apply requires a reviewer to approve in the GitHub **Environments** settings. Configure this under **Settings → Environments → prod → Required reviewers**.

---

## Datadog Monitors Included

| Monitor | Threshold (prod / dev) | Alert |
|---------|----------------------|-------|
| GKE Node CPU | 85% critical / 95% | Slack + PagerDuty |
| GKE Node Memory | 90% critical / 95% | Slack + PagerDuty |
| Cloud SQL CPU | 80% critical | Slack |
| Cloud SQL Disk | 85% critical | Slack |

All monitors are tagged with `env:<environment>` and `project:<project_id>` for filtering.

---

## Security Best Practices Enforced

- **No public IP on Cloud SQL** — private IP only via Private Service Access
- **Private GKE nodes** — egress via Cloud NAT only
- **Workload Identity Federation** — no long-lived service account keys in CI/CD
- **Workload Identity** on GKE — pods authenticate to GCP without key files
- **Shielded nodes** — Secure Boot + Integrity Monitoring enabled
- **Checkov** — blocks PRs with known security misconfigurations
- **Deletion protection** — enabled on Cloud SQL in prod
- **State in GCS with versioning** — rollback-capable state management

---

## Pro Tips

### Catch Security Issues Early
The `tf-plan.yml` workflow runs **Checkov before any plan reaches GCP**. To add org-specific exceptions:
```yaml
skip_check: CKV_GCP_999,CKV_GCP_888
```

### Managing Secrets Safely
Never put `datadog_api_key` or DB passwords in `.tfvars` files. Instead:
```bash
# Pass secrets as environment variables — Terraform picks them up automatically
export TF_VAR_datadog_api_key=$(gcloud secrets versions access latest --secret=datadog-api-key)
```

### Switching to Autopilot
Set `gke_autopilot = true` in your `.tfvars`. The `node_pools` variable is ignored in Autopilot mode — GCP manages node scaling automatically.

### Importing Existing Resources
If you have existing GCP resources to bring under Terraform management:
```bash
terraform import module.vpc.google_compute_network.vpc projects/my-project/global/networks/my-vpc
```
