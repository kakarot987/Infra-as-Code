##############################################################################
# main.tf — Root module
# GCP provider + module orchestration
##############################################################################

terraform {
  required_version = ">= 1.7.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 3.30"
    }
  }

  # Backend config is supplied per-environment via -backend-config flag
  backend "gcs" {}
}

###############################################################################
# Providers
###############################################################################

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
  api_url = "https://api.datadoghq.com/"
}

###############################################################################
# VPC Module
###############################################################################

module "vpc" {
  source = "./modules/vpc"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  network_name = "${var.environment}-vpc"

  subnets = [
    {
      name          = "${var.environment}-subnet-gke"
      ip_cidr_range = var.gke_subnet_cidr
      region        = var.region
      description   = "Subnet for GKE nodes"
    },
    {
      name          = "${var.environment}-subnet-db"
      ip_cidr_range = var.db_subnet_cidr
      region        = var.region
      description   = "Subnet for Cloud SQL private IP"
    }
  ]

  secondary_ranges = {
    "${var.environment}-subnet-gke" = [
      { range_name = "pods",     ip_cidr_range = var.pods_cidr },
      { range_name = "services", ip_cidr_range = var.services_cidr },
    ]
  }
}

###############################################################################
# GKE Module
###############################################################################

module "gke" {
  source = "./modules/gke"

  project_id   = var.project_id
  region       = var.region
  environment  = var.environment
  cluster_name = "${var.environment}-gke-cluster"

  network    = module.vpc.network_name
  subnetwork = module.vpc.subnet_names["${var.environment}-subnet-gke"]

  ip_range_pods     = "pods"
  ip_range_services = "services"

  node_pools = var.gke_node_pools

  # Autopilot mode — set to false for Standard clusters
  enable_autopilot = var.gke_autopilot
  master_authorized_cidrs = var.gke_master_authorized_cidrs
}

###############################################################################
# Cloud SQL Module
###############################################################################

module "cloudsql" {
  source = "./modules/cloudsql"

  project_id    = var.project_id
  region        = var.region
  environment   = var.environment
  instance_name = "${var.environment}-postgres"

  database_version = var.db_version
  tier             = var.db_tier
  disk_size        = var.db_disk_size

  private_network = module.vpc.network_id
  db_password     = var.db_password

  # Cloud SQL private IP requires Private Service Access peering to be ready.
  depends_on = [module.vpc]

  backup_configuration = {
    enabled            = true
    binary_log_enabled = false
    start_time         = "03:00"
    retention_days     = var.environment == "prod" ? 30 : 7
  }

  deletion_protection = var.environment == "prod" ? true : false
}

# Formatting output capture: remove after CI diagnostic.
