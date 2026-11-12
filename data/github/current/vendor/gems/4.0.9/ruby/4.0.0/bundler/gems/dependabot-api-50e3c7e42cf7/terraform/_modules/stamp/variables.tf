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

variable "stamp_replication_type" {
  description = "The replication type of the storage account stamp."
  type = string
  default = "GZRS"
}