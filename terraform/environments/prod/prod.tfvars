##############################################################################
# environments/prod/prod.tfvars
##############################################################################

project_id  = "my-project-prod"
region      = "us-central1"
environment = "prod"

# ─── Networking ──────────────────────────────────────────────────────────────
gke_subnet_cidr = "10.10.0.0/20"
db_subnet_cidr  = "10.10.16.0/24"
pods_cidr       = "10.11.0.0/16"
services_cidr   = "10.12.0.0/20"

# ─── GKE ─────────────────────────────────────────────────────────────────────
gke_autopilot = false

gke_node_pools = [
  {
    name           = "general"
    machine_type   = "e2-standard-4"
    min_node_count = 2
    max_node_count = 10
    disk_size_gb   = 100
    preemptible    = false # No preemptible in prod
  },
  {
    name           = "memory-optimized"
    machine_type   = "e2-highmem-4"
    min_node_count = 1
    max_node_count = 5
    disk_size_gb   = 100
    preemptible    = false
  }
]

# ─── Cloud SQL ────────────────────────────────────────────────────────────────
db_version   = "POSTGRES_15"
db_tier      = "db-n1-standard-4"
db_disk_size = 100

# ─── Datadog ──────────────────────────────────────────────────────────────────
datadog_notification_channels = ["@slack-prod-alerts", "@pagerduty-oncall"]
