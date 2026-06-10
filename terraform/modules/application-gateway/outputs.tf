output "public_ip_address" {
  value = azurerm_public_ip.this.ip_address
}

output "id" {
  value = azurerm_application_gateway.this.id
}
