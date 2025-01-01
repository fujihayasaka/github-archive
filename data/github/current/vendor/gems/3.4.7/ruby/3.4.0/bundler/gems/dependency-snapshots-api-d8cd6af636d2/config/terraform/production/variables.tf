variable "region" {
  type        = string
  description = "Region for Azure resources"
  # why is this eastus instead of westus? Our prod DCs are in eastus
  default     = "eastus"
}

variable "containers" {
  type        = list(string)
  description = "List of containers to create in the storage account"
  default     = [
    "snapshot-blobs"
  ]
}
