variable "name" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}

variable "app_subnet_prefixes" {
  type    = list(string)
  default = ["10.20.1.0/26"]
}

variable "private_endpoint_subnet_prefixes" {
  type    = list(string)
  default = ["10.20.2.0/27"]
}

variable "tags" {
  type = map(string)
}
