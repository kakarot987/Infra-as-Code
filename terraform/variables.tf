##############################################################################
# variables.tf — Input variable declarations
##############################################################################

###############################################################################
# GCP Core
###############################################################################

variable "project_id" {
  description = "The GCP project ID to deploy resources into."
  type        = string
}

variable "region" {
  description = "Default GCP region for resources."
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Deployment environment (dev | staging | prod)."
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

###############################################################################
# Networking
###############################################################################

variable "gke_subnet_cidr" {
  description = "Primary CIDR for the GKE node subnet."
  type        = string
}

variable "db_subnet_cidr" {
  description = "Primary CIDR for the Cloud SQL subnet."
  type        = string
}

variable "pods_cidr" {
  description = "Secondary CIDR range for GKE pods."
  type        = string
}

variable "services_cidr" {
  description = "Secondary CIDR range for GKE services."
  type        = string
}

###############################################################################
# GKE
###############################################################################

variable "gke_autopilot" {
  description = "Enable GKE Autopilot mode. Set false for Standard clusters."
  type        = bool
  default     = false
}

variable "gke_node_pools" {
  description = "List of node pool configurations (ignored in Autopilot mode)."
  type = list(object({
    name               = string
    machine_type       = string
    min_node_count     = number
    max_node_count     = number
    disk_size_gb       = number
    preemptible        = bool
  }))
  default = []
}

###############################################################################
# Cloud SQL
###############################################################################

variable "db_version" {
  description = "Cloud SQL database version."
  type        = string
  default     = "POSTGRES_15"
}

variable "db_tier" {
  description = "Cloud SQL machine tier (e.g. db-f1-micro, db-n1-standard-2)."
  type        = string
}

variable "db_disk_size" {
  description = "Cloud SQL disk size in GB."
  type        = number
  default     = 20
}

###############################################################################
# Datadog
###############################################################################

variable "datadog_api_key" {
  description = "Datadog API key (store in Secret Manager, not in tfvars)."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Datadog application key (store in Secret Manager)."
  type        = string
  sensitive   = true
}

variable "datadog_notification_channels" {
  description = "List of Datadog notification targets (e.g. @slack-alerts, @pagerduty)."
  type        = list(string)
  default     = []
}
