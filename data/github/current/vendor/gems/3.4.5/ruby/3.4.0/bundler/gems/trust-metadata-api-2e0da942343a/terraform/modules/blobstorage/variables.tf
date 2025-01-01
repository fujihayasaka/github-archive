variable "project_tags" {
  type = map(any)
  default = {
    catalog_service = "trust-metadata-api"
    project         = "trust-metadata-api"
    team            = "package-security"
  }
}

variable "env" {
  type    = string
  default = "staging"
}

variable "azure_tenant_id" {
  type = string
}

variable "azure_client_id" {
  type = string
}

variable "azure_client_secret" {
  type = string
}

variable "pagerduty_integration_url" {
  description = "PagerDuty webhook integration key for alerts"
  type        = string
}

variable "subscription_id" {
  description = "The subscription_id for the target subscription"
  type        = string
}

variable "resource_location" {
  description = "The location for the resource group"
  type        = string
}
