# Infra-as-Code Foundation — GCP

> **Template: The "Infra-as-Code" Foundation**
> Stack: **Terraform + GitHub Actions + Datadog** on Google Cloud Platform

---

## Overview

This template gives you a reusable IaC template (deployment validation required) for GCP with:

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
| `TF_VAR_db_password` | A unique, randomly generated Cloud SQL password |

### 5. Update Variable Files

Edit the following files to match your GCP project IDs:

- `terraform/environments/dev/dev.tfvars` — set `project_id`
- `terraform/environments/dev/backend.conf` — set `bucket`
- `terraform/environments/prod/prod.tfvars` — set `project_id`
- `terraform/environments/prod/backend.conf` — set `bucket`
- `gke_master_authorized_cidrs` — optionally set an explicit trusted public IP range (e.g., a VPN's `/32`) via `TF_VAR_gke_master_authorized_cidrs`. By default, there are no user-defined authorized CIDRs; do not configure `0.0.0.0/0`.

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

---

## Validation status and operator safety

**This repository contains a design template, not evidence of a successful GCP deployment.**
Run `terraform fmt -recursive`, `terraform init -backend=false`, and `terraform validate`
locally, then run a real dev plan before describing it as deployed. Verify the GKE control-plane
access strategy and Datadog monitor queries with live metrics before production usage.

For GitHub Actions, create the secrets `TF_VAR_db_password`, `TF_VAR_datadog_api_key`,
and `TF_VAR_datadog_app_key` under each **dev/prod GitHub Environment** (with distinct
database passwords). The workflows explicitly map these secrets to Terraform environment variables.
An absent secret will prevent planning or applying; nothing should fall back to a static password.
Terraform state may contain database passwords even when values are marked sensitive; restrict
and encrypt state-bucket access. If a previous static password was ever used in a deployment,
**rotate it**; removing the default does not erase Git history.

The GKE control-plane endpoint is public but protected by an explicit list of approved CIDRs.
The default empty list may prevent access from your workstation; set a restricted source
range before trying remote `kubectl`. Prefer a private endpoint or approved bastion/VPN where possible.

Production approval is not enabled merely by writing `environment: prod` in the workflow.
Configure **Settings → Environments → prod → Required reviewers** to enforce manual approval.
GitHub Actions may create billable GKE, Cloud SQL, and networking resources. Do not run an
apply without checking project, state bucket, quota, and expected costs.

### Teardown of development resources

Once the correct dev project and backend are selected and sensitive `TF_VAR_*` values are
available in your shell, run:

```bash
cd terraform
terraform init -backend-config=environments/dev/backend.conf
terraform plan -destroy -var-file=environments/dev/dev.tfvars
terraform destroy -var-file=environments/dev/dev.tfvars
```

Inspect the destroy plan carefully; do not delete the state bucket before destroying
tracked resources. Production resources have deletion protection and require separate handling.


## Checkov remediation and security decisions (November 2026)

- **Cloud SQL:** Enforces encrypted IP connections, enables PostgreSQL
  error/connection duration/host logging, and configures pgAudit for DDL and
  role audit events. An administrator must run `CREATE EXTENSION pgaudit;`
  on each database after applying. Verify TLS-capable clients and expected
  audit entries before reporting pgAudit as operational. These flags can
  restart Cloud SQL and increase log volume/cost.
- **Backups:** Backups are always enabled by the module with point-in-time
  recovery, rather than controlled by an unconstrained boolean. Check actual
  backups and retention after deployment.
- **Version policy (CKV_GCP_79 exception):** PostgreSQL 15 remains pinned
  until compatibility tests, supported-version review, rollback and a
  controlled major-upgrade plan are complete. Do not force a major upgrade
  solely to satisfy a policy checking the newest release.
- **Statement logging (CKV_GCP_111 exception):** Raw `log_statement=all` may
  leak sensitive values into centralized logs; pgAudit with controlled event
  classes is preferred. Review the audit coverage required by your organization.
- **GKE:** Production uses a private control-plane endpoint and requires
  a real `gke_security_group` for Google Groups for GKE. GKE Binary
  Authorization is enforced in prod and requires a configured organizational
  admission policy allowing approved images. Standard clusters enable Calico
  network policy; verify Autopilot compatibility independently.
- **GKE management access:** A private production endpoint cannot be reached
  directly from GitHub-hosted runners or your laptop without a proper VPN,
  bastion, private runner or other approved control-plane access path.
- **Network controls:** VPC subnet flow logs and GKE intranode visibility
  increase monitoring costs. The explicit low-priority ingress deny does
  not replace the GKE-managed cluster firewall rules; inspect them after
  creating a cluster.
- **Outstanding validation:** Checkov is a static scanner and its output
  can be affected by module expansion and variables. Review every remaining
  finding on its merits. Never globally disable Checkov to obtain a green
  check. These changes are **not** a successful GCP plan/apply.


### Scanner-specific review notes

Checkov 3.4.5 requires any inline `checkov:skip` comments to be **inside**
the resource scope. The scope-limited exceptions above address policy
limitations and explicit environment decisions, not a blanket bypass:
- `CKV_GCP_6`: the Google provider's `ssl_mode = "ENCRYPTED_ONLY"`
  enforces encrypted SQL connections; Checkov may expect the older `require_ssl`.
- `CKV_GCP_61`: flow logs are enabled on VPC subnets and intranode
  visibility on Standard clusters; Autopilot's networking is managed separately.
- `CKV_GCP_66`: Binary Authorization is enforced for production; unsigned
  development demonstration images are not production-approved.
- `CKV_GCP_69`: GKE metadata mode is set on separately managed node pools.

Confirm these operational assumptions with `terraform plan` and GCP
tests before merging. Exceptions are visible in Checkov's skipped count.
