variable "azure_client_id" {
  type    = string
  default = "spn_trust_metadata_api_tf_client_id"
}

variable "azure_client_secret" {
  type    = string
  default = "spn_trust_metadata_api_tf"
}

variable "azure_tenant_id" {
  type    = string
  default = "spn_trust_metadata_api_tf_tenant_id"
}

variable "env" {
  type    = string
  default = "staging"
}

variable "pagerduty_integration_url" {
  type    = string
  default = "https://events.pagerduty.com/integration/b5507ff65be0420cd03e23b96304517a/enqueue"
}

variable "subscription_id" {
  type    = string
  default = "a0231bbd-fed8-4abc-bc8d-dc92d3e358bf"
}

variable "resource_location" {
  type    = string
  default = "eastus"
}
