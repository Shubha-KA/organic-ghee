resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  resource_group_name = var.resource_group_name
  location            = var.location
  os_type             = "Linux"
  sku_name            = var.service_plan_sku_name
  tags                = var.tags
}

resource "azurerm_linux_function_app" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  service_plan_id     = azurerm_service_plan.this.id

  storage_account_name          = var.storage_account_name
  storage_uses_managed_identity = true
  content_share_force_disabled  = true
  https_only                    = true
  virtual_network_subnet_id     = var.virtual_network_subnet_id
  public_network_access_enabled = var.public_network_access_enabled

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                              = true
    ftps_state                             = "Disabled"
    minimum_tls_version                    = "1.2"
    scm_minimum_tls_version                = "1.2"
    http2_enabled                          = true
    vnet_route_all_enabled                 = var.virtual_network_subnet_id != null
    application_insights_connection_string = var.application_insights_connection_string

    application_stack {
      node_version = "20"
    }
  }

  app_settings = merge({
    FUNCTIONS_WORKER_RUNTIME             = "node"
    WEBSITE_RUN_FROM_PACKAGE             = "1"
    WEBSITE_CONTENTOVERVNET              = "1"
    AzureWebJobsStorage__accountName     = var.storage_account_name
    AzureWebJobsStorage__credential      = "managedidentity"
    AzureWebJobsStorage__blobServiceUri  = "https://${var.storage_account_name}.blob.core.windows.net"
    AzureWebJobsStorage__queueServiceUri = "https://${var.storage_account_name}.queue.core.windows.net"
    AzureWebJobsStorage__tableServiceUri = "https://${var.storage_account_name}.table.core.windows.net"
  }, var.app_settings)

  tags = var.tags
}
