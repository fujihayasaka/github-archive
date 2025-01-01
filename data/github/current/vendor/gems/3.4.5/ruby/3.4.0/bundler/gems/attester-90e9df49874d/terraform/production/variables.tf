variable "azure_client_id" {
  type    = string
  default = "spn_attester_prod_tf_client_id"
}

variable "azure_client_secret" {
  type    = string
  default = "spn_attester_prod_tf"
}

variable "azure_tenant_id" {
  type    = string
  default = "spn_attester_prod_tf_tenant_id"
}

variable "env" {
  type    = string
  default = "Production"
}

variable "pagerduty_integration_url" {
  type    = string
  default = "https://events.pagerduty.com/integration/c1625b6fe9cb4503c085bc01297fb79e/enqueue"
}

variable "subscription_id" {
  type    = string
  default = "56eeaa83-e372-4311-a873-55e3806dcc42"
}

variable "vault_env" {
  type    = string
  default = "production"
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

# Allow Wiz IPs (https://github.com/github/azure-rbac/blob/main/data/named_ip_locations/wiz.txt)
variable "additional_firewall_ips" {
  description = "Additional IPs (beyond the dynamically calculated ones) to be applied to the firewall rules"
  default     = []
  type        = list(string)
}
