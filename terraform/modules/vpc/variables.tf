variable "project_id"   { type = string }
variable "region"       { type = string }
variable "environment"  { type = string }
variable "network_name" { type = string }

variable "subnets" {
  type = list(object({
    name          = string
    ip_cidr_range = string
    region        = string
    description   = optional(string, "")
  }))
  default = []
}

variable "secondary_ranges" {
  type = map(list(object({
    range_name    = string
    ip_cidr_range = string
  })))
  default = {}
}
