resource "azurerm_storage_account" "this" {
  name                            = var.name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = var.account_tier
  account_replication_type        = var.account_replication_type
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = var.allow_blob_public_access
  public_network_access_enabled   = var.public_network_access_enabled
  shared_access_key_enabled       = var.shared_access_key_enabled
  default_to_oauth_authentication = true

  blob_properties {
    delete_retention_policy {
      days = var.delete_retention_days
    }
    container_delete_retention_policy {
      days = var.container_delete_retention_days
    }
    versioning_enabled = var.versioning_enabled
  }

  tags = var.tags
}

resource "azurerm_storage_queue" "orders" {
  name               = var.queue_name
  storage_account_id = azurerm_storage_account.this.id
}

resource "azurerm_storage_container" "blob" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}
