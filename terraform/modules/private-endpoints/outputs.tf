output "private_endpoint_ids" {
  value = { for key, endpoint in azurerm_private_endpoint.this : key => endpoint.id }
}
