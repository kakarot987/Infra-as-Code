##############################################################################
# modules/cloudsql/main.tf
# Reusable Cloud SQL module — PostgreSQL with private IP
##############################################################################

resource "google_sql_database_instance" "instance" {
  name             = var.instance_name
  database_version = var.database_version
  region           = var.region
  project          = var.project_id

  deletion_protection = var.deletion_protection

  settings {
    tier              = var.tier
    availability_type = var.high_availability ? "REGIONAL" : "ZONAL"
    disk_size         = var.disk_size
    disk_autoresize   = true
    user_labels       = { environment = var.environment }

    ip_configuration {
      ipv4_enabled    = false # No public IP
      private_network = var.private_network
    }

    backup_configuration {
      enabled            = var.backup_configuration.enabled
      binary_log_enabled = var.backup_configuration.binary_log_enabled
      start_time         = var.backup_configuration.start_time

      backup_retention_settings {
        retained_backups = var.backup_configuration.retention_days
      }
    }

    database_flags {
      name  = "log_checkpoints"
      value = "on"
    }

    database_flags {
      name  = "log_connections"
      value = "on"
    }

    database_flags {
      name  = "log_lock_waits"
      value = "on"
    }

    maintenance_window {
      day          = 7 # Sunday
      hour         = 3 # 3 AM
      update_track = "stable"
    }

    insights_config {
      query_insights_enabled  = true
      record_application_tags = true
      record_client_address   = false
    }
  }
}

###############################################################################
# Default Database & User
###############################################################################

resource "google_sql_database" "default" {
  name     = var.database_name
  instance = google_sql_database_instance.instance.name
  project  = var.project_id
}

resource "google_sql_user" "app_user" {
  name     = var.db_username
  instance = google_sql_database_instance.instance.name
  password = var.db_password
  project  = var.project_id
}

###############################################################################
# Outputs
###############################################################################

output "instance_name" {
  value = google_sql_database_instance.instance.name
}

output "connection_name" {
  value = google_sql_database_instance.instance.connection_name
}

output "private_ip" {
  value     = google_sql_database_instance.instance.private_ip_address
  sensitive = true
}
