variable "vault_application" {
  type = string
}

variable "vault_environment" {
  type = string
}

variable "rg_name_override" {
  type = string
}

variable "stamp_name" {
  type = string
}

# This should only be set to 'true' for dotcom-based resources (i.e. not Proxima)
variable "allow_gh_dcs" {
  type    = bool
  default = false
}

variable "cosmos_account_name_override" {
  type = string
}
