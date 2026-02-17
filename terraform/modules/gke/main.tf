##############################################################################
# modules/gke/main.tf
# Reusable GKE module — Standard or Autopilot private cluster
##############################################################################

resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # We manage node pools separately
  remove_default_node_pool = var.enable_autopilot ? null : true
  initial_node_count       = var.enable_autopilot ? null : 1

  enable_autopilot = var.enable_autopilot

  network    = var.network
  subnetwork = var.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = var.ip_range_pods
    services_secondary_range_name = var.ip_range_services
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false          # Public control plane for kubectl access
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"           # Restrict in prod to VPN/bastion IPs
      display_name = "all (restrict in prod)"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }

  release_channel {
    channel = var.release_channel
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  maintenance_policy {
    daily_maintenance_window {
      start_time = "03:00"
    }
  }

  lifecycle {
    ignore_changes = [initial_node_count]
  }
}

###############################################################################
# Node Pools (Standard mode only)
###############################################################################

resource "google_container_node_pool" "pools" {
  for_each = var.enable_autopilot ? {} : { for np in var.node_pools : np.name => np }

  name       = each.value.name
  cluster    = google_container_cluster.cluster.name
  location   = var.region
  project    = var.project_id

  autoscaling {
    min_node_count = each.value.min_node_count
    max_node_count = each.value.max_node_count
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    preemptible  = each.value.preemptible

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = {
      environment = var.environment
      pool        = each.value.name
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

###############################################################################
# Outputs
###############################################################################

output "cluster_name" {
  value = google_container_cluster.cluster.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.cluster.endpoint
  sensitive = true
}

output "cluster_ca_certificate" {
  value     = google_container_cluster.cluster.master_auth[0].cluster_ca_certificate
  sensitive = true
}
