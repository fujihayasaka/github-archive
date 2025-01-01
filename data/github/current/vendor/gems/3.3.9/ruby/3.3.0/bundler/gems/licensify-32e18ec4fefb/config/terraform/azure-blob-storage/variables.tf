variable "stamp" {
  description = "The name of the stamp the resources are deployed for i.e dotcom, prod-weu-01, prod-sdc-01, etc"
  type        = string
}

variable "location" {
  description = "the azure region to deploy to"
  type        = string
}

variable "storage_account_name" {
  description = "the name of the storage account"
  type        = string
}
