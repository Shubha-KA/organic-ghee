locals {
  environment = terraform.workspace
  is_prod     = terraform.workspace == "prod"
  prefix      = "${var.naming_prefix}-${local.environment}"

  app_service_location = coalesce(var.app_service_location, var.location)
  cosmos_location      = coalesce(var.cosmos_location, var.location)
  application_base_url = var.application_base_url != "" ? trimsuffix(var.application_base_url, "/") : "https://${local.prefix}-appsvc.azurewebsites.net"
  application_hostname = trimprefix(local.application_base_url, "https://")

  monitoring_enabled             = var.enable_monitoring
  cosmos_enabled                 = var.enable_cosmos_db
  function_enabled               = var.enable_function_app
  private_networking_enabled     = var.enable_private_networking
  front_door_enabled             = var.enable_front_door
  application_gateway_enabled    = var.enable_application_gateway
  resource_locks_enabled         = var.enable_resource_locks
  app_service_networking_enabled = local.private_networking_enabled && !contains(["F1", "D1"], var.app_service_sku_name)

  tags = merge({
    Environment = local.environment
    Project     = var.project_name
    Owner       = var.owner
    CostCenter  = var.cost_center
    ManagedBy   = "Terraform"
  }, var.extra_tags)
}
