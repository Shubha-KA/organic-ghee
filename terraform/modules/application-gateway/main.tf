locals {
  gateway_ip_configuration_name  = "${var.name}-gateway-ip"
  frontend_ip_configuration_name = "${var.name}-frontend-ip"
  frontend_port_name             = "${var.name}-http-port"
  backend_address_pool_name      = "${var.name}-backend-pool"
  backend_http_settings_name     = "${var.name}-backend-https"
  listener_name                  = "${var.name}-http-listener"
  routing_rule_name              = "${var.name}-routing-rule"
  probe_name                     = "${var.name}-health-probe"
}

resource "azurerm_public_ip" "this" {
  name                = "${var.name}-agw-pip"
  resource_group_name = var.resource_group_name
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = var.tags
}

resource "azurerm_application_gateway" "this" {
  name                = "${var.name}-agw"
  resource_group_name = var.resource_group_name
  location            = var.location
  http2_enabled       = true
  firewall_policy_id  = azurerm_web_application_firewall_policy.this.id
  tags                = var.tags

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = local.gateway_ip_configuration_name
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.this.id
  }

  frontend_port {
    name = local.frontend_port_name
    port = 80
  }

  backend_address_pool {
    name  = local.backend_address_pool_name
    fqdns = [var.backend_host_name]
  }

  probe {
    name                                      = local.probe_name
    protocol                                  = "Https"
    path                                      = "/"
    host                                      = var.backend_host_name
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = false
  }

  backend_http_settings {
    name                                = local.backend_http_settings_name
    protocol                            = "Https"
    port                                = 443
    cookie_based_affinity               = "Disabled"
    request_timeout                     = 30
    pick_host_name_from_backend_address = true
    probe_name                          = local.probe_name
  }

  http_listener {
    name                           = local.listener_name
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name
    protocol                       = "Http"
  }

  request_routing_rule {
    name                       = local.routing_rule_name
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.backend_http_settings_name
    priority                   = 100
  }
}

resource "azurerm_web_application_firewall_policy" "this" {
  name                = "${var.name}-agw-waf"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags

  policy_settings {
    enabled                     = true
    mode                        = "Prevention"
    request_body_check          = true
    file_upload_limit_in_mb     = 100
    max_request_body_size_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}
