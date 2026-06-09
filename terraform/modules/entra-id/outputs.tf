output "application_id" {
  value = azuread_application.this.client_id
}

output "service_principal_object_id" {
  value = azuread_service_principal.this.object_id
}

output "application_object_id" {
  description = "Application object id (use for federated credentials)"
  value       = azuread_application.this.object_id
}

output "tenant_id" {
  description = "Tenant id (from provider configuration)"
  value       = data.azuread_client_config.current.tenant_id
}

output "admin_client_id" {
  value = azuread_application.admin.client_id
}

output "admin_application_object_id" {
  value = azuread_application.admin.object_id
}

output "admin_service_principal_object_id" {
  value = azuread_service_principal.admin.object_id
}

output "admin_client_secret" {
  value     = azuread_application_password.admin.value
  sensitive = true
}
