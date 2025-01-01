variable "vault_environment" {
  type = string
}

variable "rg_name_override" {
  type    = string
  default = ""
}

variable "write_db_secrets_to_vault" {
  type    = bool
  default = false
}

variable "stamp_name" {
  type = string
}

# This should only be set to `true` for dotcom-based resources (i.e. not Proxima).
variable "allow_gh_dcs" {
  type    = bool
  default = false
}

variable "enable_key_based_authentication" {
  type    = bool
  default = false
}

variable "automatic_failover_enabled" {
  type    = bool
  default = true
}

variable "cosmos_account_name" {
  type = string
}

variable "additional_tags" {
  description = "Additional tags to apply to the Cosmos resource."
  type        = map(string)
  default     = {}
}

variable "storage_account_rg_name" {
  type = string
}

variable "storage_account_name" {
  description = "the name of the storage account"
  type        = string
}

variable "create_rg" {
  type    = bool
  default = true
}

variable "additional_ips" {
  type = list(string)
  default = []
}

variable "database_autoscale_max_throughput" {
  type = number
  nullable = true
  default = null
}
