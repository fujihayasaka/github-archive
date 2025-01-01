variable "stamp_name" {
  description = "The name of the stamp."
  type = string
}

variable "stamp_azure_name" {
  description = "The name of the stamp in the Azure subscription. This exists for legacy reasons and shouldn't be set on any new stamps."
  type = string
  default = null
}

variable "stamp_azure_region" {
  description = "The Azure region of the stamp."
  type = string
}

variable "stamp_elasticsearch_cluster_name" {
  description = "The name of the Elasticsearch cluster."
  type = string
  default = null
}

variable "stamp_elasticsearch_username" {
  description = "The username to connect to the Elasticsearch cluster."
  type = string
  default = null
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
