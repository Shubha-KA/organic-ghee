resource "azuread_application" "this" {
  display_name = var.name
  owners       = var.owners
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
}

# Federated credentials for GitHub Actions OIDC
resource "azuread_application_federated_identity_credential" "github_oidc" {
  for_each = local.federated_map

  application_id = azuread_application.this.id
  display_name   = each.key
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = each.value
  audiences      = var.audiences
}

resource "random_uuid" "admin_role" {}

resource "azuread_application" "admin" {
  display_name     = "${var.name}-admin"
  owners           = var.owners
  sign_in_audience = "AzureADMyOrg"

  app_role {
    allowed_member_types = ["User"]
    description          = "Administrators who can manage dishes and orders."
    display_name         = "Administrator"
    enabled              = true
    id                   = random_uuid.admin_role.result
    value                = "Admin"
  }

  web {
    homepage_url  = var.admin_logout_url
    logout_url    = var.admin_logout_url
    redirect_uris = var.admin_redirect_uris
  }
}

resource "azuread_service_principal" "admin" {
  client_id = azuread_application.admin.client_id
}

resource "azuread_application_password" "admin" {
  application_id = azuread_application.admin.id
  display_name   = "terraform-managed"
}

resource "azuread_app_role_assignment" "admin" {
  for_each = var.admin_member_object_ids

  app_role_id         = random_uuid.admin_role.result
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.admin.object_id
}
