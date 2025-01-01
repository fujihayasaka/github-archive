/*
The process for rotating HMAC keys:

1. Open a PR to swap the active and passive keys.
2. Apply the Terraform and deploy the application.
3. Taint the now passive key i.e. terraform taint random_password.your_resource_name.
This will destroy the existing value and create a new one during the next apply.
4. Apply the Terraform and redeploy the application
*/

// TWIRP_HMAC_KEYS
resource "random_password" "twirp_hmac_key_green" {
  length  = 64
  special = false
  upper   = false
}

resource "random_password" "twirp_hmac_key_blue" {
  length  = 64
  special = false
  upper   = false
}

locals {
  twirp_hmac_key_active  = random_password.twirp_hmac_key_green.result
  twirp_hmac_key_passive = random_password.twirp_hmac_key_blue.result
}

resource "octovault_application_secret" "twirp_hmac_keys" {
  application = "osslicensecompliance"
  environment = var.stamp_name

  key   = "TWIRP_HMAC_KEYS"
  value = "${local.twirp_hmac_key_active} ${local.twirp_hmac_key_passive}"
}
