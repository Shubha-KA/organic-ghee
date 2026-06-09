variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "account_tier" {
  type    = string
  default = "Standard"
}

variable "account_replication_type" {
  type    = string
  default = "LRS"
}

variable "allow_blob_public_access" {
  type    = bool
  default = false
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "shared_access_key_enabled" {
  type    = bool
  default = true
}

variable "queue_name" {
  type    = string
  default = "order-notifications"
}

variable "container_delete_retention_days" {
  type    = number
  default = 7
}

variable "container_name" {
  type    = string
  default = "appblob"
}

variable "versioning_enabled" {
  type    = bool
  default = true
}

variable "delete_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type = map(string)
}
