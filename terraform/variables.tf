variable "subscription_id" {
  description = "Azure subscription ID"
  type        = string
  default     = ""
}

variable "tenant_id" {
  description = "Microsoft Entra tenant ID"
  type        = string
  default     = ""
}

variable "project_name" {
  type    = string
  default = "organic-ghee"
}

variable "naming_prefix" {
  type    = string
  default = "sapp"
}

variable "owner" {
  type    = string
  default = "cloud-team"
}

variable "cost_center" {
  type    = string
  default = "CC1001"
}

variable "extra_tags" {
  type    = map(string)
  default = {}
}

variable "location" {
  type    = string
  default = "eastus"
}

variable "app_service_location" {
  type    = string
  default = null
}

variable "app_service_sku_name" {
  description = "App Service SKU name, for example F1 for Dev or P1v3 for Prod"
  type        = string
  default     = "F1"
}

variable "application_base_url" {
  description = "Public application URL used by Microsoft Entra ID redirect and logout flows; Prod must use the approved Front Door custom domain"
  type        = string
  default     = ""

  validation {
    condition     = var.application_base_url == "" || (startswith(var.application_base_url, "https://") && !endswith(trimsuffix(var.application_base_url, "/"), ".azurewebsites.net"))
    error_message = "application_base_url must use HTTPS and must not use an azurewebsites.net hostname."
  }
}

variable "disable_app_service_public_access" {
  description = "Disable direct App Service public access after a Front Door custom domain is configured"
  type        = bool
  default     = false
}

variable "storage_replication_type" {
  type    = string
  default = "LRS"
}

variable "github_org" {
  type    = string
  default = "Shubha-KA"
}

variable "github_repo" {
  type    = string
  default = "organic-ghee"
}

variable "admin_member_object_ids" {
  description = "Entra user or group object IDs assigned the application Administrator role"
  type        = set(string)
  default     = []
}

variable "database_connection_string" {
  description = "Optional existing MongoDB connection string stored into Key Vault when Cosmos DB is disabled"
  type        = string
  sensitive   = true
  default     = ""
}

variable "enable_monitoring" {
  type    = bool
  default = false
}

variable "enable_cosmos_db" {
  type    = bool
  default = false
}

variable "enable_function_app" {
  type    = bool
  default = false
}

variable "enable_private_networking" {
  type    = bool
  default = false
}

variable "enable_front_door" {
  type    = bool
  default = false
}

variable "enable_resource_locks" {
  type    = bool
  default = false
}

variable "cosmos_free_tier_enabled" {
  type    = bool
  default = false
}

variable "cosmos_backup_type" {
  type    = string
  default = "Continuous"

  validation {
    condition     = contains(["Continuous", "Periodic"], var.cosmos_backup_type)
    error_message = "cosmos_backup_type must be Continuous or Periodic."
  }
}

variable "function_service_plan_sku_name" {
  type    = string
  default = "EP1"
}

variable "notification_sender_user_id" {
  description = "Entra user object ID or user principal name used by the Function to send Microsoft Graph email"
  type        = string
  default     = ""
}

variable "contact_notification_recipient" {
  description = "Mailbox that receives contact form notifications"
  type        = string
  default     = ""
}

variable "log_retention_days" {
  type    = number
  default = 30
}

variable "vnet_address_space" {
  type    = list(string)
  default = ["10.20.0.0/16"]
}
