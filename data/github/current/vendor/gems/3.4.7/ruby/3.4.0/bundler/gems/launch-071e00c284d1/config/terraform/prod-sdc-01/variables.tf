variable "storage_account_regions" {
  description = "A map of regions to storage account indices"
  type        = map(list(number))
  nullable    = false
}