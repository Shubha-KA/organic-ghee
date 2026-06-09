locals {
  endpoints = merge({
    key_vault = {
      target_id        = var.key_vault_id
      subresource_name = "vault"
      zone_key         = "key_vault"
    }
    storage_blob = {
      target_id        = var.storage_account_id
      subresource_name = "blob"
      zone_key         = "storage_blob"
    }
    storage_queue = {
      target_id        = var.storage_account_id
      subresource_name = "queue"
      zone_key         = "storage_queue"
    }
    storage_file = {
      target_id        = var.storage_account_id
      subresource_name = "file"
      zone_key         = "storage_file"
    }
    storage_table = {
      target_id        = var.storage_account_id
      subresource_name = "table"
      zone_key         = "storage_table"
    }
    }, var.enable_cosmosdb_endpoint ? {
    cosmos_mongo = {
      target_id        = var.cosmosdb_account_id
      subresource_name = "MongoDB"
      zone_key         = "cosmos_mongo"
    }
    } : {}, var.enable_app_service_endpoint ? {
    app_service = {
      target_id        = var.app_service_id
      subresource_name = "sites"
      zone_key         = "app_services"
    }
    } : {}, var.enable_function_app_endpoint ? {
    function_app = {
      target_id        = var.function_app_id
      subresource_name = "sites"
      zone_key         = "app_services"
    }
  } : {})

  dns_zones = merge({
    key_vault     = "privatelink.vaultcore.azure.net"
    storage_blob  = "privatelink.blob.core.windows.net"
    storage_queue = "privatelink.queue.core.windows.net"
    storage_file  = "privatelink.file.core.windows.net"
    storage_table = "privatelink.table.core.windows.net"
    }, var.enable_cosmosdb_endpoint ? {
    cosmos_mongo = "privatelink.mongo.cosmos.azure.com"
    } : {}, var.enable_app_service_endpoint || var.enable_function_app_endpoint ? {
    app_services = "privatelink.azurewebsites.net"
  } : {})
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.dns_zones

  name                = each.value
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.dns_zones

  name                  = "${var.name}-${each.key}-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.endpoints

  name                = "${var.name}-${each.key}-pe"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "${var.name}-${each.key}-psc"
    private_connection_resource_id = each.value.target_id
    subresource_names              = [each.value.subresource_name]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.value.zone_key].id]
  }
}
