variable "azure_client_id" {
  type    = string
  default = "spn_trust_metadata_api_${STAMP_NAME_UNDERSCORED}_tf_client_id"
}

variable "azure_client_secret" {
  type    = string
  default = "spn_trust_metadata_api_${STAMP_NAME_UNDERSCORED}_tf"
}

variable "azure_tenant_id" {
  type    = string
  default = "spn_trust_metadata_api_${STAMP_NAME_UNDERSCORED}_tf_tenant_id"
}

variable "env" {
  type    = string
  default = "${STAMP_NAME}"
}

variable "pagerduty_integration_url" {
  type    = string
  default = "https://events.pagerduty.com/integration/${PAGERDUTY_INTEGRATION_KEY}/enqueue"
}

variable "subscription_id" {
  type    = string
  default = "${AZURE_SUBSCRIPTION}"
}

variable "resource_location" {
  type    = string
  default = "${AZURE_REGION}"
}
