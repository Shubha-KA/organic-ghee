resource "azurerm_cdn_frontdoor_profile" "this" {
  name                = "${var.name}-afd"
  resource_group_name = var.resource_group_name
  sku_name            = "Premium_AzureFrontDoor"
  tags                = var.tags
}

resource "azurerm_cdn_frontdoor_endpoint" "this" {
  name                     = "${var.name}-endpoint"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  tags                     = var.tags
}

resource "azurerm_cdn_frontdoor_origin_group" "this" {
  name                     = "app-origin-group"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  session_affinity_enabled = false

  health_probe {
    interval_in_seconds = 120
    path                = "/health"
    protocol            = "Https"
    request_type        = "GET"
  }

  load_balancing {
    additional_latency_in_milliseconds = 0
    sample_size                        = 4
    successful_samples_required        = 3
  }
}

resource "azurerm_cdn_frontdoor_origin" "this" {
  name                           = "app-service"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.this.id
  enabled                        = true
  host_name                      = var.origin_host_name
  origin_host_header             = var.origin_host_name
  http_port                      = 80
  https_port                     = 443
  certificate_name_check_enabled = true

  private_link {
    location               = var.origin_location
    private_link_target_id = var.origin_resource_id
    target_type            = "sites"
    request_message        = "Front Door private origin access"
  }
}

resource "azurerm_cdn_frontdoor_route" "this" {
  name                            = "app-route"
  cdn_frontdoor_endpoint_id       = azurerm_cdn_frontdoor_endpoint.this.id
  cdn_frontdoor_origin_group_id   = azurerm_cdn_frontdoor_origin_group.this.id
  cdn_frontdoor_origin_ids        = [azurerm_cdn_frontdoor_origin.this.id]
  patterns_to_match               = ["/*"]
  supported_protocols             = ["Http", "Https"]
  forwarding_protocol             = "HttpsOnly"
  https_redirect_enabled          = true
  link_to_default_domain          = true
  cdn_frontdoor_custom_domain_ids = var.enable_custom_domain ? [azurerm_cdn_frontdoor_custom_domain.this[0].id] : []
}

resource "azurerm_cdn_frontdoor_custom_domain" "this" {
  count = var.enable_custom_domain ? 1 : 0

  name                     = "${var.name}-domain"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id
  host_name                = var.custom_domain_host_name

  tls {
    certificate_type = "ManagedCertificate"
    minimum_version  = "TLS12"
  }
}

resource "azurerm_cdn_frontdoor_firewall_policy" "this" {
  name                              = replace("${var.name}-waf", "-", "")
  resource_group_name               = var.resource_group_name
  sku_name                          = azurerm_cdn_frontdoor_profile.this.sku_name
  enabled                           = true
  mode                              = "Prevention"
  custom_block_response_status_code = 403

  managed_rule {
    type    = "DefaultRuleSet"
    version = "2.1"
    action  = "Block"
  }

  managed_rule {
    type    = "Microsoft_BotManagerRuleSet"
    version = "1.1"
    action  = "Block"
  }

  tags = var.tags
}

resource "azurerm_cdn_frontdoor_security_policy" "this" {
  name                     = "${var.name}-security-policy"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.this.id

  security_policies {
    firewall {
      cdn_frontdoor_firewall_policy_id = azurerm_cdn_frontdoor_firewall_policy.this.id

      association {
        patterns_to_match = ["/*"]

        domain {
          cdn_frontdoor_domain_id = azurerm_cdn_frontdoor_endpoint.this.id
        }
      }
    }
  }
}
