project_name  = "organic-ghee"
naming_prefix = "sapp"
location      = "eastus"
owner         = "platform-team"
cost_center   = "CC2001"
github_org    = "Shubha-KA"
github_repo   = "organic-ghee"

extra_tags = {
  Stage = "prod"
}

app_service_sku_name           = "P1v3"
storage_replication_type       = "ZRS"
function_service_plan_sku_name = "EP1"
notification_sender_user_id    = ""
contact_notification_recipient = ""

enable_monitoring         = true
enable_cosmos_db          = true
enable_function_app       = true
enable_private_networking = true
enable_front_door         = true
enable_resource_locks     = true

cosmos_free_tier_enabled = false
cosmos_backup_type       = "Continuous"

# Override with TF_VAR_application_base_url using the approved Front Door custom domain before apply.
application_base_url              = "https://organic-ghee.invalid"
disable_app_service_public_access = true
