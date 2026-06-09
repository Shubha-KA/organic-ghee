resource "azurerm_service_plan" "this" {
  name                = "${var.name}-plan"
  location            = var.location
  resource_group_name = var.resource_group_name
  os_type             = "Linux"
  sku_name            = var.sku_name

  tags = var.tags
}

resource "azurerm_linux_web_app" "this" {
  name                                           = var.name
  location                                       = var.location
  resource_group_name                            = var.resource_group_name
  service_plan_id                                = azurerm_service_plan.this.id
  https_only                                     = true
  public_network_access_enabled                  = var.defer_public_network_lockdown ? true : var.public_network_access_enabled
  virtual_network_subnet_id                      = var.virtual_network_subnet_id
  ftp_publish_basic_authentication_enabled       = false
  webdeploy_publish_basic_authentication_enabled = false

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on               = var.always_on
    ftps_state              = "Disabled"
    health_check_path       = var.always_on ? var.health_check_path : null
    minimum_tls_version     = "1.2"
    scm_minimum_tls_version = "1.2"
    http2_enabled           = true
    vnet_route_all_enabled  = var.virtual_network_subnet_id != null

    application_stack {
      node_version = var.node_version
    }
  }

  app_settings = var.app_settings

  tags = var.tags

  lifecycle {
    ignore_changes = [public_network_access_enabled]
  }
}
