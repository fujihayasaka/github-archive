variable "azure_client_id" {
  type    = string
  default = "spn_trust_metadata_api_prod_weu_01_tf_client_id"
}

variable "azure_client_secret" {
  type    = string
  default = "spn_trust_metadata_api_prod_weu_01_tf"
}

variable "azure_tenant_id" {
  type    = string
  default = "spn_trust_metadata_api_prod_weu_01_tf_tenant_id"
}

variable "env" {
  type    = string
  default = "prod-weu-01"
}

variable "pagerduty_integration_url" {
  type    = string
  default = "https://events.pagerduty.com/integration/5e5d952fddb34b02d02b669984af6855/enqueue"
}

variable "subscription_id" {
  type    = string
  default = "56eeaa83-e372-4311-a873-55e3806dcc42"
}

variable "resource_location" {
  type    = string
  default = "westeurope"
}
