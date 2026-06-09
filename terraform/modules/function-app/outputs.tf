output "id" {
  value = azurerm_linux_function_app.this.id
}

output "principal_id" {
  value = azurerm_linux_function_app.this.identity[0].principal_id
}

output "default_hostname" {
  value = azurerm_linux_function_app.this.default_hostname
}
