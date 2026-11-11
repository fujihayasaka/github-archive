variable "subscription_id_val" {
  description = "Azure subscription ID for Dependabot-api"
  type        = string
  default     = "843be593-cd7a-457a-a7e6-f71f2e9ad014"
}

output "subscription_id" {
  value = var.subscription_id_val
}
