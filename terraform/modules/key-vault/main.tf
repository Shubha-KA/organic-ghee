resource "azurerm_key_vault" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = var.sku_name
  purge_protection_enabled      = var.purge_protection_enabled
  soft_delete_retention_days    = var.soft_delete_retention_days
  enabled_for_disk_encryption   = true
  rbac_authorization_enabled    = var.enable_rbac
  public_network_access_enabled = var.defer_public_network_lockdown ? true : var.public_network_access_enabled
  network_acls {
    default_action = var.defer_public_network_lockdown || var.public_network_access_enabled ? "Allow" : "Deny"
    bypass         = "AzureServices"
  }
  tags = var.tags

  lifecycle {
    ignore_changes = [
      public_network_access_enabled,
      network_acls,
    ]
  }
}
