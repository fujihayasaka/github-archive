variable "resource_group_name" {
  description = "The resource group name for Kusto resources"
  type        = string
}

variable "cluster_name" {
  description = "The name of the cluster"
  type        = string
}

variable "sku_name" {
  description = "The SKU name for Kusto resources"
  type        = string
}

variable "auto_scale_minimum_instances" {
  description = "The minimum number of instances for auto scale"
  type        = number
}

variable "auto_scale_maximum_instances" {
  description = "The maximum number of instances for auto scale"
  type        = number
}

variable "reader_spn" {
  description = "The client id of the runtime service principal"
  type        = set(string)
}

variable "environment" {
  type = string
}

variable "region" {
  description = "The region for Kusto resources"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The log analytics workspace id"
  type        = string
}

variable "app" {
  description = "The application name"
  type        = string
}

variable "jit_group_id" {
  description = "The JIT group id"
  type        = string
}
