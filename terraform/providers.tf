provider "azurerm" {
  features {
  }

  # Authentication options: Azure CLI or Service Principal
  # For Azure CLI auth, run `az login` locally and omit client_id/client_secret
  # Example service principal auth (uncomment to use):
  # subscription_id = var.subscription_id
  # client_id       = var.client_id
  # client_secret   = var.client_secret
  # tenant_id       = var.tenant_id
}

provider "azuread" {
  # Uses Azure CLI or environment/service principal
}

provider "azapi" {}

provider "random" {}
