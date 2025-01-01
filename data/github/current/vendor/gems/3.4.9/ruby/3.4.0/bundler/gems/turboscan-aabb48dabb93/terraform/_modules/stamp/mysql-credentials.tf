locals {
  stamp_mysql_credential_prefix = var.stamp_mysql_credential_prefix != null ? var.stamp_mysql_credential_prefix : "${upper(replace(var.stamp_name, "-", "_"))}_TURBOSCAN_"
}

data "octovault_application_secret" "mysql_user" {
  application = "turboscan"
  environment = "mysql-credentials"
  key = "${local.stamp_mysql_credential_prefix}RW_USER"
}

resource "octovault_application_secret" "mysql_user" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "MYSQL_USERNAME"
  value = data.octovault_application_secret.mysql_user.value
}

data "octovault_application_secret" "mysql_password" {
  application = "turboscan"
  environment = "mysql-credentials"
  key = "${local.stamp_mysql_credential_prefix}RW_PASS"
}

resource "octovault_application_secret" "mysql_password" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "MYSQL_PASSWORD"
  value = data.octovault_application_secret.mysql_password.value
}
