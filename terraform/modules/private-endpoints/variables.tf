variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "key_vault_id" {
  type = string
}

variable "storage_account_id" {
  type = string
}

variable "cosmosdb_account_id" {
  type    = string
  default = null
}

variable "enable_cosmosdb_endpoint" {
  type    = bool
  default = false
}

variable "app_service_id" {
  type    = string
  default = null
}

variable "enable_app_service_endpoint" {
  type    = bool
  default = false
}

variable "enable_app_services_dns_zone" {
  type    = bool
  default = false
}

variable "function_app_id" {
  type    = string
  default = null
}

variable "enable_function_app_endpoint" {
  type    = bool
  default = false
}

variable "tags" {
  type = map(string)
}
