variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "database_name" {
  type    = string
  default = "organic-ghee"
}

variable "free_tier_enabled" {
  type    = bool
  default = false
}

variable "public_network_access_enabled" {
  type    = bool
  default = true
}

variable "backup_type" {
  type    = string
  default = "Continuous"
}

variable "tags" {
  type = map(string)
}
