variable "stamp_name" {
  description = "The name of the stamp."
  type = string
}

variable "stamp_aqueduct_api_key_version" {
  description = "The version of the Aqueduct API key."
  type = number
  default = 0
}

variable "stamp_mysql_credential_prefix" {
  description = "The prefix for MySQL credential variables in Vault."
  type = string
  default = null
}
