resource "random_password" "internal_api_hmac_key_red" {
  length = 64
  special = false
  upper = false
}

resource "random_password" "internal_api_hmac_key_blue" {
  length = 64
  special = false
  upper = false
}

locals {
  internal_api_hmac_key_active = random_password.internal_api_hmac_key_red.result
  internal_api_hmac_key_passive = random_password.internal_api_hmac_key_blue.result
}

resource "octovault_application_secret" "github_twirp_hmac_key_turboghas" {
  application = "turboghas"
  environment = "${var.stamp_name}"

  key = "GITHUB_TWIRP_HMAC_KEY"
  value = "${local.internal_api_hmac_key_active}"
}
resource "octovault_application_secret" "api_internal_twirp_hmac_keys_for_turbghas_github" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "API_INTERNAL_TWIRP_HMAC_KEYS_FOR_TURBOGHAS"
  value = "${local.internal_api_hmac_key_active} ${local.internal_api_hmac_key_passive}"
}
