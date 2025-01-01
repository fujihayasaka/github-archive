variable "project_tags" {
  type = map(any)
  default = {
    catalog_service = "attester"
    project         = "attester"
    team            = "package-security"
  }
}

variable "resource_location" {
  type    = string
  default = "East US"
}

variable "env" {
  type    = string
  default = "Staging"
}

variable "vault_env" {
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

variable "subscription_id" {
  description = "The subscription_id for the target subscription"
  type        = string
}

variable "pagerduty_integration_url" {
  description = "PagerDuty webhook integration key for alerts"
  type        = string
}

variable "public_network_access_enabled" {
  description = "Enable public network access to the key vault"
  type        = bool
  default     = false
}

variable "default_action" {
  type    = string
  default = "Allow"
}

variable "allow_gh_dcs" {
  description = "Allows connection by GitHub DataCenters to the KV via public connections"
  type        = bool
  default     = false
}

variable "additional_ips_to_allow" {
  description = "The set of additional CIDR IP Addresses or ranges for the KV to allow via IP filter"
  default     = []
  type        = list(string)
}
