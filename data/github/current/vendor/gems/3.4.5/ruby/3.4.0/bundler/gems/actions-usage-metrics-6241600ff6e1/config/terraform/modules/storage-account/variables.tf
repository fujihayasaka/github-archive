variable "resource_group_name" {
  description = "The resource group name for Kusto resources"
  type        = string
}

variable "account_name" {
  description = "The name of the storage account"
  type        = string
}

variable "region" {
  description = "The region for the resources"
  type        = string
}

variable "app" {
  description = "The application name"
  type        = string
}

variable "environment" {
  type = string
}

variable "log_analytics_workspace_id" {
  description = "The log analytics workspace id"
  type        = string
}