data "octovault_application_secret" "launch_deployer_hmac_secret_github" {
  application = "github"
  environment = "${var.stamp_name}"
  key = "LAUNCH_DEPLOYER_HMAC_SECRET"
}

resource "octovault_application_secret" "launch_deployer_hmac_secret" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "LAUNCH_DEPLOYER_HMAC_SECRET"
  value = "${data.octovault_application_secret.launch_deployer_hmac_secret_github.value}"
}
