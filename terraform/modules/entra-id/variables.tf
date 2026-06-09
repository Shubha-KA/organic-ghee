variable "name" {
  type = string
}

variable "owners" {
  type    = list(string)
  default = []
}

variable "admin_redirect_uris" {
  description = "OIDC callback URIs for the administrator web application"
  type        = list(string)
}

variable "admin_logout_url" {
  description = "Post logout URL for the administrator web application"
  type        = string
}

data "azuread_client_config" "current" {}

locals {
  federated_map = {
    dev  = "repo:${var.github_org}/${var.github_repo}:environment:dev"
    prod = "repo:${var.github_org}/${var.github_repo}:environment:prod"
  }
}


variable "github_org" {
  description = "GitHub organization for federated credentials"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name for federated credentials"
  type        = string
}

variable "audiences" {
  description = "OIDC audiences for federated credentials"
  type        = list(string)
  default     = ["api://AzureADTokenExchange"]
}

variable "admin_member_object_ids" {
  description = "Entra user or group object IDs assigned to the administrator app role"
  type        = set(string)
  default     = []
}
