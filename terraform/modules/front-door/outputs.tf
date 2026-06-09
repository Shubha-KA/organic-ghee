output "endpoint_hostname" {
  value = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "custom_domain_validation_token" {
  value = azurerm_cdn_frontdoor_custom_domain.this.validation_token
}
