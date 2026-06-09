data "azuread_client_config" "current" {}
data "azurerm_client_config" "current" {}
data "azuread_service_principal" "microsoft_graph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

module "resource_group" {
  source   = "./modules/resource-group"
  name     = "${local.prefix}-rg"
  location = var.location
  tags     = local.tags
}

module "network" {
  count = local.private_networking_enabled ? 1 : 0

  source              = "./modules/network"
  name                = local.prefix
  resource_group_name = module.resource_group.name
  location            = var.location
  address_space       = var.vnet_address_space
  tags                = local.tags
}

module "storage" {
  source                        = "./modules/storage-account"
  name                          = lower(substr(replace("${local.prefix}sa", "-", ""), 0, 24))
  resource_group_name           = module.resource_group.name
  location                      = var.location
  account_replication_type      = var.storage_replication_type
  container_name                = "appblob"
  queue_name                    = "order-notifications"
  allow_blob_public_access      = false
  public_network_access_enabled = !local.private_networking_enabled
  shared_access_key_enabled     = !local.is_prod
  tags                          = local.tags
}

module "entra" {
  source                  = "./modules/entra-id"
  name                    = "${local.prefix}-app"
  github_org              = var.github_org
  github_repo             = var.github_repo
  admin_redirect_uris     = ["${local.application_base_url}/auth/entra/callback"]
  admin_logout_url        = "${local.application_base_url}/"
  admin_member_object_ids = var.admin_member_object_ids
}

module "key_vault" {
  source                        = "./modules/key-vault"
  name                          = "${local.prefix}-kv"
  location                      = var.location
  resource_group_name           = module.resource_group.name
  tenant_id                     = var.tenant_id != "" ? var.tenant_id : data.azuread_client_config.current.tenant_id
  purge_protection_enabled      = local.is_prod
  soft_delete_retention_days    = local.is_prod ? 90 : 7
  public_network_access_enabled = !local.private_networking_enabled
  defer_public_network_lockdown = local.private_networking_enabled
  tags                          = local.tags
}

module "monitoring" {
  count = local.monitoring_enabled ? 1 : 0

  source              = "./modules/monitoring"
  name                = local.prefix
  resource_group_name = module.resource_group.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags
}

module "cosmos" {
  count = local.cosmos_enabled ? 1 : 0

  source                        = "./modules/cosmos-db"
  name                          = lower("${local.prefix}-mongo")
  resource_group_name           = module.resource_group.name
  location                      = var.location
  database_name                 = "organic-ghee"
  free_tier_enabled             = var.cosmos_free_tier_enabled
  public_network_access_enabled = !local.private_networking_enabled
  backup_type                   = var.cosmos_backup_type
  tags                          = local.tags
}

resource "random_password" "session_secret" {
  length  = 64
  special = true
}

resource "azurerm_key_vault_secret" "session_secret" {
  name         = "session-secret"
  value        = random_password.session_secret.result
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployment_key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "entra_admin_client_secret" {
  name         = "entra-admin-client-secret"
  value        = module.entra.admin_client_secret
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployment_key_vault_secrets_officer]
}

resource "azurerm_key_vault_secret" "database_connection_string" {
  count = local.cosmos_enabled || var.database_connection_string != "" ? 1 : 0

  name         = "database-connection-string"
  value        = local.cosmos_enabled ? module.cosmos[0].connection_string : var.database_connection_string
  key_vault_id = module.key_vault.id

  depends_on = [azurerm_role_assignment.deployment_key_vault_secrets_officer]
}

locals {
  app_settings = merge({
    NODE_ENV                       = local.is_prod ? "production" : "development"
    WEBSITE_RUN_FROM_PACKAGE       = "1"
    KEY_VAULT_NAME                 = module.key_vault.name
    STORAGE_ACCOUNT_NAME           = module.storage.account_name
    BLOB_CONTAINER                 = module.storage.container_name
    ORDER_NOTIFICATIONS_QUEUE      = module.storage.queue_name
    SESSION_SECRET                 = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.session_secret.versionless_id})"
    ENTRA_TENANT_ID                = var.tenant_id != "" ? var.tenant_id : data.azuread_client_config.current.tenant_id
    ENTRA_CLIENT_ID                = module.entra.admin_client_id
    ENTRA_CLIENT_SECRET            = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.entra_admin_client_secret.versionless_id})"
    ENTRA_ADMIN_ROLE               = "Admin"
    ENTRA_REDIRECT_URI             = "${local.application_base_url}/auth/entra/callback"
    ENTRA_POST_LOGOUT_REDIRECT_URI = "${local.application_base_url}/"
    }, local.monitoring_enabled ? {
    APPLICATIONINSIGHTS_CONNECTION_STRING = module.monitoring[0].application_insights_connection_string
    } : {}, length(azurerm_key_vault_secret.database_connection_string) > 0 ? {
    AZURE_COSMOS_CONNECTIONSTRING = "@Microsoft.KeyVault(SecretUri=${azurerm_key_vault_secret.database_connection_string[0].versionless_id})"
  } : {})
}

module "app_service" {
  source                        = "./modules/app-service"
  name                          = "${local.prefix}-appsvc"
  location                      = local.app_service_location
  resource_group_name           = module.resource_group.name
  sku_name                      = var.app_service_sku_name
  always_on                     = var.app_service_sku_name != "F1" && var.app_service_sku_name != "D1"
  virtual_network_subnet_id     = local.private_networking_enabled ? module.network[0].app_subnet_id : null
  public_network_access_enabled = !var.disable_app_service_public_access
  defer_public_network_lockdown = local.front_door_enabled && var.disable_app_service_public_access
  app_settings                  = local.app_settings
  tags                          = local.tags
}

module "function_app" {
  count = local.function_enabled ? 1 : 0

  source                                 = "./modules/function-app"
  name                                   = "${local.prefix}-notifications-func"
  resource_group_name                    = module.resource_group.name
  location                               = var.location
  storage_account_name                   = module.storage.account_name
  service_plan_sku_name                  = var.function_service_plan_sku_name
  virtual_network_subnet_id              = local.private_networking_enabled ? module.network[0].app_subnet_id : null
  application_insights_connection_string = local.monitoring_enabled ? module.monitoring[0].application_insights_connection_string : null
  public_network_access_enabled          = !local.private_networking_enabled
  app_settings = {
    OrderNotifications__queueServiceUri = "https://${module.storage.account_name}.queue.core.windows.net"
    OrderNotifications__credential      = "managedidentity"
    ORDER_NOTIFICATIONS_QUEUE           = module.storage.queue_name
    KEY_VAULT_NAME                      = module.key_vault.name
    NOTIFICATION_SENDER_USER_ID         = var.notification_sender_user_id
    CONTACT_NOTIFICATION_RECIPIENT      = var.contact_notification_recipient
  }
  tags = local.tags
}

module "private_endpoints" {
  count = local.private_networking_enabled ? 1 : 0

  source                       = "./modules/private-endpoints"
  name                         = local.prefix
  resource_group_name          = module.resource_group.name
  location                     = var.location
  vnet_id                      = module.network[0].vnet_id
  subnet_id                    = module.network[0].private_endpoint_subnet_id
  key_vault_id                 = module.key_vault.id
  storage_account_id           = module.storage.account_id
  cosmosdb_account_id          = local.cosmos_enabled ? module.cosmos[0].id : null
  enable_cosmosdb_endpoint     = local.cosmos_enabled
  app_service_id               = module.app_service.id
  enable_app_service_endpoint  = true
  function_app_id              = local.function_enabled ? module.function_app[0].id : null
  enable_function_app_endpoint = local.function_enabled
  tags                         = local.tags
}

module "front_door" {
  count = local.front_door_enabled ? 1 : 0

  source                  = "./modules/front-door"
  name                    = local.prefix
  resource_group_name     = module.resource_group.name
  origin_host_name        = module.app_service.default_site_hostname
  origin_resource_id      = module.app_service.id
  origin_location         = local.app_service_location
  custom_domain_host_name = local.application_hostname
  tags                    = local.tags
}

resource "azapi_update_resource" "key_vault_network_lockdown" {
  count = local.private_networking_enabled ? 1 : 0

  type        = "Microsoft.KeyVault/vaults@2023-07-01"
  resource_id = module.key_vault.id
  body = {
    properties = {
      publicNetworkAccess = "Disabled"
      networkAcls = {
        bypass        = "AzureServices"
        defaultAction = "Deny"
      }
    }
  }

  depends_on = [
    azurerm_key_vault_secret.session_secret,
    azurerm_key_vault_secret.entra_admin_client_secret,
    azurerm_key_vault_secret.database_connection_string,
    module.private_endpoints,
  ]
}

resource "azapi_update_resource" "app_service_network_lockdown" {
  count = local.front_door_enabled && var.disable_app_service_public_access ? 1 : 0

  type        = "Microsoft.Web/sites@2024-04-01"
  resource_id = module.app_service.id
  body = {
    properties = {
      publicNetworkAccess = "Disabled"
    }
  }

  depends_on = [
    module.front_door,
    module.private_endpoints,
  ]
}

locals {
  subscription_id = var.subscription_id != "" ? var.subscription_id : data.azurerm_client_config.current.subscription_id
}

resource "azurerm_role_assignment" "deployment_contributor" {
  scope                            = module.resource_group.id
  role_definition_name             = "Contributor"
  principal_id                     = module.entra.service_principal_object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deployment_access_administrator" {
  scope                            = module.resource_group.id
  role_definition_name             = "User Access Administrator"
  principal_id                     = module.entra.service_principal_object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "deployment_key_vault_secrets_officer" {
  scope                            = module.key_vault.id
  role_definition_name             = "Key Vault Secrets Officer"
  principal_id                     = module.entra.service_principal_object_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "app_key_vault_secrets_user" {
  scope                            = module.key_vault.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.app_service.identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "app_storage_blob_contributor" {
  scope                            = module.storage.account_id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = module.app_service.identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "app_storage_queue_contributor" {
  scope                            = module.storage.account_id
  role_definition_name             = "Storage Queue Data Contributor"
  principal_id                     = module.app_service.identity_principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "function_storage_blob_owner" {
  count = local.function_enabled ? 1 : 0

  scope                            = module.storage.account_id
  role_definition_name             = "Storage Blob Data Owner"
  principal_id                     = module.function_app[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "function_storage_queue_contributor" {
  count = local.function_enabled ? 1 : 0

  scope                            = module.storage.account_id
  role_definition_name             = "Storage Queue Data Contributor"
  principal_id                     = module.function_app[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "function_storage_table_contributor" {
  count = local.function_enabled ? 1 : 0

  scope                            = module.storage.account_id
  role_definition_name             = "Storage Table Data Contributor"
  principal_id                     = module.function_app[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "function_key_vault_secrets_user" {
  count = local.function_enabled ? 1 : 0

  scope                            = module.key_vault.id
  role_definition_name             = "Key Vault Secrets User"
  principal_id                     = module.function_app[0].principal_id
  skip_service_principal_aad_check = true
}

resource "azuread_app_role_assignment" "function_graph_mail_send" {
  count = local.function_enabled ? 1 : 0

  app_role_id         = data.azuread_service_principal.microsoft_graph.app_role_ids["Mail.Send"]
  principal_object_id = module.function_app[0].principal_id
  resource_object_id  = data.azuread_service_principal.microsoft_graph.object_id
}

resource "azurerm_monitor_diagnostic_setting" "app_service" {
  count = local.monitoring_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.app_service.id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  count = local.monitoring_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.key_vault.id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_log {
    category_group = "audit"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage" {
  count = local.monitoring_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.storage.account_id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_blob" {
  count = local.monitoring_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.storage.blob_service_id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_queue" {
  count = local.monitoring_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.storage.queue_service_id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "cosmos" {
  count = local.monitoring_enabled && local.cosmos_enabled ? 1 : 0

  name                       = "send-to-log-analytics"
  target_resource_id         = module.cosmos[0].id
  log_analytics_workspace_id = module.monitoring[0].workspace_id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "Requests"
  }
}

resource "azurerm_management_lock" "key_vault" {
  count = local.resource_locks_enabled ? 1 : 0

  name       = "protect-key-vault"
  scope      = module.key_vault.id
  lock_level = "CanNotDelete"
}

resource "azurerm_management_lock" "storage" {
  count = local.resource_locks_enabled ? 1 : 0

  name       = "protect-storage"
  scope      = module.storage.account_id
  lock_level = "CanNotDelete"
}
