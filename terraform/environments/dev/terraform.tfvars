project_name         = "organic-ghee"
naming_prefix        = "sapp"
location             = "eastus"
app_service_location = "australiaeast"
cosmos_location      = "australiaeast"
owner                = "dev-team"
cost_center          = "CC1001"
github_org           = "Shubha-KA"
github_repo          = "organic-ghee"

extra_tags = {
  Stage = "dev"
}

app_service_sku_name     = "F1"
storage_replication_type = "LRS"

enable_monitoring          = true
enable_cosmos_db           = true
enable_function_app        = false
enable_private_networking  = true
enable_front_door          = false
enable_application_gateway = true
enable_resource_locks      = true

cosmos_free_tier_enabled = false
cosmos_backup_type       = "Continuous"
