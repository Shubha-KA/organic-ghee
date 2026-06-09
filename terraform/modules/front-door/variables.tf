variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "origin_host_name" {
  type = string
}

variable "origin_resource_id" {
  type = string
}

variable "origin_location" {
  type = string
}

variable "custom_domain_host_name" {
  type = string
}

variable "tags" {
  type = map(string)
}
