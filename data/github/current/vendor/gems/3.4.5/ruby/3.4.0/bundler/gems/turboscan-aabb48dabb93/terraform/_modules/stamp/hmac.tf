resource "random_password" "turboscan_hmac_key_red" {
  length = 64
  special = false
  upper = false

  keepers = {
    rotation = "Invalidated due to https://github.com/github/security/issues/6209."
  }
}

resource "random_password" "turboscan_hmac_key_blue" {
  length = 64
  special = false
  upper = false
}

locals {
  turboscan_hmac_key_active = random_password.turboscan_hmac_key_blue.result
  turboscan_hmac_key_passive = random_password.turboscan_hmac_key_red.result
}

resource "octovault_application_secret" "turboscan_hmac_key" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "TURBOSCAN_HMAC_KEY"
  value = "${local.turboscan_hmac_key_active} ${local.turboscan_hmac_key_passive}"
}

resource "octovault_application_secret" "api_internal_twirp_hmac_keys_for_turboscan" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "API_INTERNAL_TWIRP_HMAC_KEYS_FOR_TURBOSCAN"
  value = "${local.turboscan_hmac_key_active}"
}

resource "octovault_application_secret" "turboscan_hmac_key_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "TURBOSCAN_HMAC_KEY"
  value = "${local.turboscan_hmac_key_active}"
}

resource "octovault_application_secret" "api_internal_twirp_hmac_keys_for_turboscan_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "API_INTERNAL_TWIRP_HMAC_KEYS_FOR_TURBOSCAN"
  value = "${local.turboscan_hmac_key_active} ${local.turboscan_hmac_key_passive}"
}
