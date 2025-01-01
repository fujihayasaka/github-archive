variable "azure_client_id" {
  type    = string
  default = "spn_attester_non_prod_tf_client_id"
}

variable "azure_client_secret" {
  type    = string
  default = "spn_attester_non_prod_tf"
}

variable "azure_tenant_id" {
  type    = string
  default = "spn_attester_non_prod_tf_tenant_id"
}

variable "env" {
  type    = string
  default = "Staging"
}

variable "pagerduty_integration_url" {
  type    = string
  default = "https://events.pagerduty.com/integration/a49c0b1aee5e4904d062f7e34660ac2b/enqueue"
}

variable "subscription_id" {
  type    = string
  default = "a0231bbd-fed8-4abc-bc8d-dc92d3e358bf"
}

variable "vault_env" {
  type    = string
  default = "staging"
}

variable "public_network_access_enabled" {
  type    = bool
  default = false
}

variable "default_action" {
  type    = string
  default = "Deny"
}

variable "allow_gh_dcs" {
  description = "Allows connection by GitHub DataCenters to the KV via public connections"
  type        = bool
  default     = false
}
