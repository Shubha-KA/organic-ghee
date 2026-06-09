variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "sku_name" {
  type    = string
  default = "F1"
}

variable "node_version" {
  type    = string
  default = "20-lts"
}

variable "always_on" {
  type    = bool
  default = false
}

variable "app_settings" {
  type    = map(string)
  default = {}
}

variable "virtual_network_subnet_id" {
  type    = string
  default = null
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "defer_public_network_lockdown" {
  type    = bool
  default = false
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "tags" {
  type = map(string)
}
