variable "spn_id" {
  description = "The client id of the runtime service principal"
  type        = string
}

variable "stamp" {
  description = "The name of the stamp (e.g. staff-wus2-1). Should only contain lowercase letters and hyphens"
  type        = string
}

variable "region" {
  description = "The azure region for stamp resources, must be same as kusto cluster being followed"
  type        = string
}

variable "app" {
  description = "The name of the app (actions-usage-metrics)"
  type        = string
}

variable "jit_group_id" {
  description = "The jit group id"
  type        = string
}

variable "kusto_cluster_sku_name" {
  description = "The name of the kusto cluster SKU (e.g. Standard_L32as_v3)"
  type        = string
}
