variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "storage_account_name" {
  type = string
}

variable "service_plan_sku_name" {
  type    = string
  default = "EP1"
}

variable "virtual_network_subnet_id" {
  type    = string
  default = null
}

variable "application_insights_connection_string" {
  type      = string
  sensitive = true
  default   = null
}

variable "public_network_access_enabled" {
  type    = bool
  default = false
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "tags" {
  type = map(string)
}
