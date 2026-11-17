##############################################################################
# monitoring.tf — Datadog Infrastructure Monitoring
# Provisions monitors, dashboards, and synthetic checks via the Datadog provider
##############################################################################

locals {
  env_tag     = "env:${var.environment}"
  project_tag = "project:${var.project_id}"
  common_tags = [local.env_tag, local.project_tag, "managed-by:terraform"]
  notify      = join(" ", var.datadog_notification_channels)
  is_prod     = var.environment == "prod"

  # Thresholds tighten in production
  cpu_threshold_critical = local.is_prod ? 85 : 95
  cpu_threshold_warning  = local.is_prod ? 70 : 85
  mem_threshold_critical = local.is_prod ? 90 : 95
  mem_threshold_warning  = local.is_prod ? 80 : 90
}

###############################################################################
# GKE Node CPU Monitor
###############################################################################

resource "datadog_monitor" "gke_node_cpu" {
  name    = "[${upper(var.environment)}] GKE Node CPU High"
  type    = "metric alert"
  message = <<-EOT
    ## GKE Node CPU Utilization High

    CPU on node {{host.name}} in cluster ${module.gke.cluster_name} (${var.environment}) is {{value}}%.

    **Action:**
    - Check for runaway pods: `kubectl top pods -A --sort-by=cpu`
    - Consider scaling the node pool or adjusting HPA settings.

    ${local.notify}
  EOT

  query = "avg(last_5m):avg:kubernetes.cpu.usage.total{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} / avg:kubernetes.cpu.limits{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} * 100 > ${local.cpu_threshold_critical}"

  monitor_thresholds {
    critical = local.cpu_threshold_critical
    warning  = local.cpu_threshold_warning
  }

  notify_no_data    = false
  renotify_interval = 60
  tags              = local.common_tags
}

###############################################################################
# GKE Node Memory Monitor
###############################################################################

resource "datadog_monitor" "gke_node_memory" {
  name    = "[${upper(var.environment)}] GKE Node Memory High"
  type    = "metric alert"
  message = <<-EOT
    ## GKE Node Memory Utilization High

    Memory on node {{host.name}} is at {{value}}%.

    **Action:**
    - Identify high-memory pods: `kubectl top pods -A --sort-by=memory`
    - Review resource requests/limits and consider vertical scaling.

    ${local.notify}
  EOT

  query = "avg(last_5m):avg:kubernetes.memory.usage{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} / avg:kubernetes.memory.limits{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} * 100 > ${local.mem_threshold_critical}"

  monitor_thresholds {
    critical = local.mem_threshold_critical
    warning  = local.mem_threshold_warning
  }

  notify_no_data    = false
  renotify_interval = 60
  tags              = local.common_tags
}

###############################################################################
# Cloud SQL CPU Monitor
###############################################################################

resource "datadog_monitor" "cloudsql_cpu" {
  name    = "[${upper(var.environment)}] Cloud SQL CPU High"
  type    = "metric alert"
  message = <<-EOT
    ## Cloud SQL CPU Utilization High

    Instance: ${module.cloudsql.instance_name} — CPU at {{value}}%.

    **Action:**
    - Identify long-running queries via Cloud SQL Insights.
    - Consider upgrading instance tier or adding read replicas.

    ${local.notify}
  EOT

  query = "avg(last_10m):avg:gcp.cloudsql.database.cpu.utilization{${local.env_tag},database_id:${var.project_id}:${module.cloudsql.instance_name}} * 100 > 80"

  monitor_thresholds {
    critical = 80
    warning  = 65
  }

  notify_no_data    = true
  no_data_timeframe = 30
  renotify_interval = 30
  tags              = local.common_tags
}

###############################################################################
# Cloud SQL Disk Utilization Monitor
###############################################################################

resource "datadog_monitor" "cloudsql_disk" {
  name    = "[${upper(var.environment)}] Cloud SQL Disk Usage High"
  type    = "metric alert"
  message = <<-EOT
    ## Cloud SQL Disk Usage High

    Disk on ${module.cloudsql.instance_name} is at {{value}}%.

    **Action:**
    - Enable storage auto-resize in Cloud SQL settings.
    - Archive or purge old data.
    - Consider increasing disk allocation.

    ${local.notify}
  EOT

  query = "avg(last_15m):avg:gcp.cloudsql.database.disk.utilization{${local.env_tag},database_id:${var.project_id}:${module.cloudsql.instance_name}} * 100 > 85"

  monitor_thresholds {
    critical = 85
    warning  = 70
  }

  notify_no_data    = true
  no_data_timeframe = 30
  tags              = local.common_tags
}

###############################################################################
# Infrastructure Dashboard
###############################################################################

resource "datadog_dashboard" "infra_overview" {
  title       = "${upper(var.environment)} — Infrastructure Overview"
  description = "GKE cluster and Cloud SQL health dashboard — managed by Terraform"
  layout_type = "ordered"

  widget {
    group_definition {
      title       = "GKE Cluster — ${module.gke.cluster_name}"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title = "Node CPU Utilization (%)"
          request {
            q            = "avg:kubernetes.cpu.usage.total{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} / avg:kubernetes.cpu.limits{${local.env_tag}} by {host} * 100"
            display_type = "line"
          }
          yaxis {
            min = "0"
            max = "100"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Node Memory Utilization (%)"
          request {
            q            = "avg:kubernetes.memory.usage{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {host} / avg:kubernetes.memory.limits{${local.env_tag}} by {host} * 100"
            display_type = "line"
          }
          yaxis {
            min = "0"
            max = "100"
          }
        }
      }

      widget {
        toplist_definition {
          title = "Top Pods by CPU"
          request {
            q = "top(avg:kubernetes.cpu.usage.total{${local.env_tag},cluster_name:${module.gke.cluster_name}} by {pod_name}, 10, 'mean', 'desc')"
          }
        }
      }
    }
  }

  widget {
    group_definition {
      title       = "Cloud SQL — ${module.cloudsql.instance_name}"
      layout_type = "ordered"

      widget {
        timeseries_definition {
          title = "CPU Utilization (%)"
          request {
            q            = "avg:gcp.cloudsql.database.cpu.utilization{${local.env_tag}} * 100"
            display_type = "line"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Disk Utilization (%)"
          request {
            q            = "avg:gcp.cloudsql.database.disk.utilization{${local.env_tag}} * 100"
            display_type = "area"
          }
        }
      }

      widget {
        timeseries_definition {
          title = "Database Connections"
          request {
            q            = "avg:gcp.cloudsql.database.postgresql.num_backends{${local.env_tag}}"
            display_type = "bars"
          }
        }
      }
    }
  }

  tags = local.common_tags
}
