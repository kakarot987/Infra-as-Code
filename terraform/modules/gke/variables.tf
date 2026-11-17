variable "project_id" { type = string }
variable "region" { type = string }
variable "environment" { type = string }
variable "cluster_name" { type = string }
variable "network" { type = string }
variable "subnetwork" { type = string }
variable "ip_range_pods" { type = string }
variable "ip_range_services" { type = string }

variable "enable_autopilot" {
  type    = bool
  default = false
}

variable "release_channel" {
  type    = string
  default = "REGULAR"
}

variable "node_pools" {
  type = list(object({
    name           = string
    machine_type   = string
    min_node_count = number
    max_node_count = number
    disk_size_gb   = number
    preemptible    = bool
  }))
  default = []
}

variable "master_authorized_cidrs" {
  description = "Explicit trusted CIDRs for the public GKE control-plane endpoint. Empty denies workstation access."
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []

  validation {
    condition = alltrue([
      for entry in var.master_authorized_cidrs :
      can(cidrhost(entry.cidr_block, 0)) && !contains(["0.0.0.0/0", "::/0"], entry.cidr_block)
    ])
    error_message = "Supply valid, restricted CIDRs; allow-all ranges are not permitted."
  }
}

variable "gke_security_group" {
  description = "Google Groups for GKE RBAC security group, e.g. gke-security-groups@your-domain. Required for production."
  type        = string
  default     = ""
}
