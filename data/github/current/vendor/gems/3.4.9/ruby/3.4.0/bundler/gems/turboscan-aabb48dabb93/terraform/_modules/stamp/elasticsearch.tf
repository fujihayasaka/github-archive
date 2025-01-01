locals {
  stamp_elasticsearch_cluster_name = var.stamp_elasticsearch_cluster_name != null ? var.stamp_elasticsearch_cluster_name : "proxima_search_es8_${replace(var.stamp_name, "-", "_")}"
  stamp_elasticsearch_username = var.stamp_elasticsearch_username != null ? var.stamp_elasticsearch_username : local.stamp_elasticsearch_cluster_name
}

data "octovault_application_secret" "elasticsearch_users" {
  application = "puppet"
  environment = "production"
  key = "github::elasticsearch::users::${local.stamp_elasticsearch_cluster_name}"
}

locals {
  elasticsearch_users = jsondecode(data.octovault_application_secret.elasticsearch_users.value)
  elasticsearch_password = [for user in local.elasticsearch_users : user.password if user.name == local.stamp_elasticsearch_username][0]
}

resource "octovault_application_secret" "elasticsearch_password" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "ES_PASSWORD"
  value = "${local.elasticsearch_password}"
}
