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

variable "acr_public_network_access" {
  description = "Public network access setting (Enabled or Disabled)"
  type        = string
  default     = "Enabled"
}

variable "acr_cache_source_repo" {
  description = "Source repository for cache rule"
  type        = string
  default     = "ghcr.io/dependabot/*"
}

variable "acr_cache_target_repo" {
  description = "Target repository for cache rule"
  type        = string
  default     = "ghcr.io/dependabot/*"
}

variable "apim_publisher_email" {
  description = "Email associated to the public API"
  type        = string
}

variable "apim_circuit_breaker_request_count" {
  description = "Number of failures within the specified interval that will trigger the circuit breaker. Possible values are between 1 and 10000."
  type        = number
  default     = 10000
}

variable "apim_circuit_breaker_interval" {
  description = "Time window over which failures are counted, in ISO 8601 format."
  type        = string
  default     = "PT1M"
}

variable "apim_circuit_breaker_trip_duration" {
  description = "Duration for which the circuit remains open before retrying, in ISO 8601 format."
  type        = string
  default     = "PT5M"
}