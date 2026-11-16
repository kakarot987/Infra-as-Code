##############################################################################
# modules/vpc/main.tf
# Reusable VPC module — custom mode VPC with private subnets
##############################################################################

resource "google_compute_network" "vpc" {
  name                    = var.network_name
  auto_create_subnetworks = false
  project                 = var.project_id
  description             = "Managed ${var.environment} infrastructure VPC"
}

resource "google_compute_subnetwork" "subnets" {
  for_each = { for s in var.subnets : s.name => s }

  name          = each.value.name
  ip_cidr_range = each.value.ip_cidr_range
  region        = each.value.region
  network       = google_compute_network.vpc.id
  project       = var.project_id
  description   = lookup(each.value, "description", "")

  private_ip_google_access = true

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }

  dynamic "secondary_ip_range" {
    for_each = lookup(var.secondary_ranges, each.key, [])
    content {
      range_name    = secondary_ip_range.value.range_name
      ip_cidr_range = secondary_ip_range.value.ip_cidr_range
    }
  }
}

# Explicit VPC firewall rule; GKE-managed allow rules at higher priority
# are evaluated before this deny. Keep ingress closed by default.
resource "google_compute_firewall" "deny_unapproved_ingress" {
  name          = "${var.network_name}-deny-unapproved-ingress"
  project       = var.project_id
  network       = google_compute_network.vpc.name
  direction     = "INGRESS"
  priority      = 65534
  source_ranges = ["0.0.0.0/0"]

  deny {
    protocol = "all"
  }
}

# Cloud NAT — allows private nodes to reach internet (pull images, etc.)
resource "google_compute_router" "nat_router" {
  name    = "${var.network_name}-nat-router"
  region  = var.region
  network = google_compute_network.vpc.id
  project = var.project_id
}

resource "google_compute_router_nat" "nat" {
  name                               = "${var.network_name}-nat"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Private Service Access — required for Cloud SQL private IP
resource "google_compute_global_address" "private_service_range" {
  name          = "${var.network_name}-private-svc-range"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  project       = var.project_id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_range.name]
}

###############################################################################
# Outputs
###############################################################################

output "network_name" {
  value = google_compute_network.vpc.name
}

output "network_id" {
  value = google_compute_network.vpc.id
}

output "network_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnet_names" {
  value = { for k, v in google_compute_subnetwork.subnets : k => v.name }
}

output "subnet_self_links" {
  value = { for k, v in google_compute_subnetwork.subnets : k => v.self_link }
}
