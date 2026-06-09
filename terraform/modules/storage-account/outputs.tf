output "account_name" {
  value = azurerm_storage_account.this.name
}

output "container_name" {
  value = azurerm_storage_container.blob.name
}

output "account_id" {
  value = azurerm_storage_account.this.id
}

output "queue_name" {
  value = azurerm_storage_queue.orders.name
}

output "blob_endpoint" {
  value = azurerm_storage_account.this.primary_blob_endpoint
}

output "blob_service_id" {
  value = "${azurerm_storage_account.this.id}/blobServices/default"
}

output "queue_service_id" {
  value = "${azurerm_storage_account.this.id}/queueServices/default"
}
