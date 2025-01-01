variable "name" {
  description = "The diagnostics settings name"
  type        = string
}

variable "kusto_cluster_id" {
  description = "The Kusto cluster id for which to configure diagnostics"
  type        = string
}

variable "log_analytics_workspace_id" {
  description = "The log analytics workspace id"
  type        = string
}
