resource "random_password" "turboghas_hmac_key_red" {
  length = 64
  special = false
  upper = false
}

resource "random_password" "turboghas_hmac_key_blue" {
  length = 64
  special = false
  upper = false
}

locals {
  turboghas_hmac_key_active = random_password.turboghas_hmac_key_red.result
  turboghas_hmac_key_passive = random_password.turboghas_hmac_key_blue.result
}

resource "octovault_application_secret" "turboghas_hmac_key" {
  application = "turboghas"
  environment = "${var.stamp_name}"

  key = "TURBOGHAS_HMAC_KEY"
  value = "${local.turboghas_hmac_key_active} ${local.turboghas_hmac_key_passive}"
}

resource "octovault_application_secret" "turboghas_hmac_key_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "TURBOGHAS_HMAC_KEY"
  value = "${local.turboghas_hmac_key_active}"
}
