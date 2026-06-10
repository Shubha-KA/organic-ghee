output "resource_group_name" {
  value = module.resource_group.name
}

output "app_service_url" {
  value = local.front_door_enabled ? local.application_base_url : "https://${module.app_service.default_site_hostname}"
}

output "storage_account_name" {
  value = module.storage.account_name
}

output "queue_name" {
  value = module.storage.queue_name
}

output "key_vault_name" {
  value = module.key_vault.name
}

output "deployment_entra_client_id" {
  value = module.entra.application_id
}

output "admin_entra_client_id" {
  value = module.entra.admin_client_id
}

output "entra_tenant_id" {
  value = module.entra.tenant_id
}

output "function_app_hostname" {
  value = local.function_enabled ? module.function_app[0].default_hostname : null
}

output "cosmos_endpoint" {
  value = local.cosmos_enabled ? module.cosmos[0].endpoint : null
}

output "front_door_custom_domain_validation_token" {
  value     = local.front_door_enabled ? module.front_door[0].custom_domain_validation_token : null
  sensitive = true
}

output "application_gateway_public_ip" {
  value = local.application_gateway_enabled ? module.application_gateway[0].public_ip_address : null
}
