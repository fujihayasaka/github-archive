variable "vault_application" {
  description = "The name of the application that desired secret belongs to in Octovault."
  type        = string
}

variable "vault_environment" {
  description = "The application's corresponding deployment environment"
  type        = string
}

variable "catalog_service_name" {
  description = "The catalog service name used when generating the SPN"
  type        = string
}
