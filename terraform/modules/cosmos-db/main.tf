resource "azurerm_cosmosdb_account" "this" {
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  offer_type                    = "Standard"
  kind                          = "MongoDB"
  mongo_server_version          = "4.2"
  free_tier_enabled             = var.free_tier_enabled
  public_network_access_enabled = var.public_network_access_enabled
  minimal_tls_version           = "Tls12"

  capabilities {
    name = "EnableMongo"
  }

  consistency_policy {
    consistency_level = "Session"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  backup {
    type               = var.backup_type
    tier               = var.backup_type == "Continuous" ? "Continuous7Days" : null
    storage_redundancy = var.backup_type == "Periodic" ? "Geo" : null
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_mongo_database" "this" {
  name                = var.database_name
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.this.name
}
