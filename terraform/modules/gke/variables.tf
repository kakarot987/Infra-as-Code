variable "project_id"    { type = string }
variable "region"        { type = string }
variable "environment"   { type = string }
variable "cluster_name"  { type = string }
variable "network"       { type = string }
variable "subnetwork"    { type = string }
variable "ip_range_pods"     { type = string }
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
