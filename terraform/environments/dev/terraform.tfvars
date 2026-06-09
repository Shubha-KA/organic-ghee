project_name         = "organic-ghee"
naming_prefix        = "sapp"
location             = "eastus"
app_service_location = "australiaeast"
owner                = "dev-team"
cost_center          = "CC1001"
github_org           = "Shubha-KA"
github_repo          = "organic-ghee"

extra_tags = {
  Stage = "dev"
}

app_service_sku_name     = "F1"
storage_replication_type = "LRS"

enable_monitoring         = false
enable_cosmos_db          = false
enable_function_app       = false
enable_private_networking = false
enable_front_door         = false
enable_resource_locks     = false

cosmos_free_tier_enabled = false
