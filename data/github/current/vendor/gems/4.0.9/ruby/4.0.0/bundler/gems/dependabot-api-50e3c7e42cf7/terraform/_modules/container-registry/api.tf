locals {
  xml_content = replace(
    file("${path.module}/acr-policy.xml"),
    "ACR_LOGIN_SERVER",
    azurerm_container_registry.container_registry.login_server
  )
}

resource "azurerm_api_management" "acr_apim" {
  name                = "dependabot-acr-apim-${replace(coalesce(var.stamp_azure_name, var.stamp_name), "-", "")}"
  location            = var.stamp_azure_region
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  publisher_name      = "GitHub Dependabot"
  publisher_email     = var.apim_publisher_email
  sku_name            = "Basic_1"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    catalog_service : "github/dependabot-api"
  }
}

resource "azurerm_api_management_api" "acr_api" {
  name                = "acr-proxy-api"
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  api_management_name = azurerm_api_management.acr_apim.name
  revision            = "1"
  display_name        = "ACR Proxy API"
  protocols           = ["https"]
  service_url         = "https://${azurerm_container_registry.container_registry.login_server}"
  subscription_required = false
}

resource "azurerm_api_management_api_operation" "proxy_all_get" {
  operation_id        = "proxy-all-get"
  api_name            = azurerm_api_management_api.acr_api.name
  api_management_name = azurerm_api_management.acr_apim.name
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  display_name        = "Proxy All GET Requests"
  method              = "GET"
  url_template        = "/{*path}"
  description         = "Proxy GET requests to ACR"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_api_operation" "proxy_all_head" {
  operation_id        = "proxy-all-head"
  api_name            = azurerm_api_management_api.acr_api.name
  api_management_name = azurerm_api_management.acr_apim.name
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  display_name        = "Proxy All HEAD Requests"
  method              = "HEAD"
  url_template        = "/{*path}"
  description         = "Proxy HEAD requests to ACR"

  template_parameter {
    name     = "path"
    type     = "string"
    required = true
  }
}

resource "azurerm_api_management_backend" "acr_backend" {
  name                = "acr-backend"
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name
  api_management_name = azurerm_api_management.acr_apim.name
  protocol            = "http"
  url                 = "https://${azurerm_container_registry.container_registry.login_server}"
  description         = "Azure Container Registry Backend"

  # This rule will act as a crude rate limit
  circuit_breaker_rule {
      name = "acr-request-limit-breaker"
      failure_condition {
        count             = var.apim_circuit_breaker_request_count
        interval_duration = var.apim_circuit_breaker_interval
        status_code_range {
          min = 200
          max = 599
        }
      }
      trip_duration = var.apim_circuit_breaker_trip_duration
      accept_retry_after_enabled = true
  }
}

resource "azurerm_api_management_api_policy" "acr_policy" {
  api_name            = azurerm_api_management_api.acr_api.name
  api_management_name = azurerm_api_management.acr_apim.name
  resource_group_name = data.azurerm_resource_group.dependabot_api_resource_group.name

  xml_content = local.xml_content 
}

# AcrPull role assignment in `azure-config` repo
# see https://github.com/github/azure-config/pull/1995

output "apim_gateway_url" {
  description = "API Management Gateway URL"
  value       = azurerm_api_management.acr_apim.gateway_url
}

output "apim_principal_id" {
  description = "APIM Managed Identity Principal ID"
  value       = azurerm_api_management.acr_apim.identity[0].principal_id
}