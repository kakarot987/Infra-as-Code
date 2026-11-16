variable "project_id"       { type = string }
variable "region"           { type = string }
variable "environment"      { type = string }
variable "instance_name"    { type = string }
variable "database_version" {
  type    = string
  default = "POSTGRES_15"
}
variable "tier"             { type = string }
variable "disk_size"        {
  type = number
  default = 20
}
variable "private_network"  { type = string }
variable "deletion_protection" {
  type = bool
  default = true
}
variable "high_availability"   {
  type = bool
  default = false
}
variable "database_name"    {
  type = string
  default = "app"
}
variable "db_username"      {
  type = string
  default = "app_user"
}
variable "db_password"      {
  type = string
  sensitive = true
  description = "Password for the Cloud SQL database"
}

variable "backup_configuration" {
  type = object({
    enabled            = bool
    binary_log_enabled = bool
    start_time         = string
    retention_days     = number
  })
  default = {
    enabled            = true
    binary_log_enabled = false
    start_time         = "03:00"
    retention_days     = 7
  }
}
