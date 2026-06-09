terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

provider "azurerm" {
  features {
  }
}

variable "location" {
  default = "eastus"
}

variable "resource_group_name" {
  default = "tfstate-rg"
}

variable "storage_account_name_prefix" {
  type        = string
  default     = "tfstate"
  description = "Prefix for storage account name"
}

variable "state_blob_data_contributor_principal_id" {
  description = "Optional principal object ID granted access to read and write Terraform state blobs"
  type        = string
  default     = ""
}

variable "enable_resource_lock" {
  description = "Protect the Terraform state resource group from accidental deletion"
  type        = bool
  default     = true
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  storage_account_name = "${var.storage_account_name_prefix}${random_id.suffix.hex}"
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_storage_account" "state" {
  name                            = lower(replace(local.storage_account_name, "-", ""))
  resource_group_name             = azurerm_resource_group.state.name
  location                        = azurerm_resource_group.state.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_name  = azurerm_storage_account.state.name
  container_access_type = "private"
}

resource "azurerm_role_assignment" "state_blob_data_contributor" {
  count = var.state_blob_data_contributor_principal_id == "" ? 0 : 1

  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.state_blob_data_contributor_principal_id
}

resource "azurerm_management_lock" "state" {
  count = var.enable_resource_lock ? 1 : 0

  name       = "protect-terraform-state"
  scope      = azurerm_resource_group.state.id
  lock_level = "CanNotDelete"
  notes      = "Protects remote Terraform state resources from accidental deletion."
}

output "storage_account_name" {
  description = "Name of the storage account for Terraform state"
  value       = azurerm_storage_account.state.name
}

output "container_name" {
  description = "Name of the blob container for state"
  value       = azurerm_storage_container.tfstate.name
}
