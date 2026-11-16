##############################################################################
# modules/gke/main.tf
# Reusable GKE module — Standard or Autopilot private cluster
##############################################################################

#checkov:skip=CKV_GCP_69:GKE_METADATA is enabled on separately managed google_container_node_pool.pools, as verified by the node-pool check.
resource "google_container_cluster" "cluster" {
  name     = var.cluster_name
  location = var.region
  project  = var.project_id

  # We manage node pools separately
  remove_default_node_pool = var.enable_autopilot ? null : true
  initial_node_count       = var.enable_autopilot ? null : 1

  enable_autopilot = var.enable_autopilot
  resource_labels = {
    environment = var.environment
    managed_by  = "terraform"
  }

  # Standard-cluster traffic visibility; cloud logging costs must be evaluated.
  enable_intranode_visibility = !var.enable_autopilot

  master_auth {
    client_certificate_config {
      issue_client_certificate = false
    }
  }

  # Production requires an organization-approved identity group.
  dynamic "authenticator_groups_config" {
    for_each = var.gke_security_group == "" ? [] : [var.gke_security_group]
    content {
      security_group = authenticator_groups_config.value
    }
  }

  # Production must use an organization-configured Binary Authorization policy.
  binary_authorization {
    evaluation_mode = var.environment == "prod" ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  network    = var.network
  subnetwork = var.subnetwork

  ip_allocation_policy {
    cluster_secondary_range_name  = var.ip_range_pods
    services_secondary_range_name = var.ip_range_services
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = var.environment == "prod" # Private production endpoint requires a trusted access path
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Only explicitly trusted CIDRs can access the public API endpoint.
  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr_block
        display_name = cidr_blocks.value.display_name
      }
    }
  }

  # Calico policy is configured for Standard; Autopilot manages its policy engine.
  dynamic "network_policy" {
    for_each = var.enable_autopilot ? [] : [1]
    content {
      enabled  = true
      provider = "CALICO"
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
    dynamic "network_policy_config" {
      for_each = var.enable_autopilot ? [] : [1]
      content { disabled = false }
    }
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
    precondition {
      condition     = var.environment != "prod" || var.gke_security_group != ""
      error_message = "Set gke_security_group to a real Google Groups for GKE security group for production."
    }
  }
}

###############################################################################
# Node Pools (Standard mode only)
###############################################################################

resource "google_container_node_pool" "pools" {
  for_each = var.enable_autopilot ? {} : { for np in var.node_pools : np.name => np }

  name     = each.value.name
  cluster  = google_container_cluster.cluster.name
  location = var.region
  project  = var.project_id

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
