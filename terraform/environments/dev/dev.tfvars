##############################################################################
# environments/dev/dev.tfvars
##############################################################################

project_id  = "my-project-dev"
region      = "us-central1"
environment = "dev"

# ─── Networking ──────────────────────────────────────────────────────────────
gke_subnet_cidr = "10.0.0.0/20"
db_subnet_cidr  = "10.0.16.0/24"
pods_cidr       = "10.1.0.0/16"
services_cidr   = "10.2.0.0/20"

# ─── GKE ─────────────────────────────────────────────────────────────────────
gke_autopilot = false

gke_node_pools = [
  {
    name           = "general"
    machine_type   = "e2-standard-2"
    min_node_count = 1
    max_node_count = 3
    disk_size_gb   = 50
    preemptible    = true # Cost savings in dev
  }
]

# ─── Cloud SQL ────────────────────────────────────────────────────────────────
db_version   = "POSTGRES_15"
db_tier      = "db-f1-micro"
db_disk_size = 10

# ─── Datadog ──────────────────────────────────────────────────────────────────
# Sensitive values should come from GitHub Secrets / Secret Manager
# datadog_api_key = set via TF_VAR_datadog_api_key env variable
# datadog_app_key = set via TF_VAR_datadog_app_key env variable

datadog_notification_channels = ["@slack-dev-alerts"]
