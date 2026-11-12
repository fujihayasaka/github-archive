variable "region" {
  type        = string
  description = "Region for Azure resources"
  default     = "westus"
}

variable "containers" {
  type        = list(string)
  description = "List of containers to create in the storage account"
  default     = [
    "snapshot-blobs"
  ]
}