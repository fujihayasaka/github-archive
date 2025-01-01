resource "tls_private_key" "github_app_private_key" {
  algorithm = "RSA"
  rsa_bits = 2048
}

resource "octovault_application_secret" "github_app_private_key" {
  application = "turboscan"
  environment = "${var.stamp_name}"

  key = "GITHUB_APP_PRIVATE_KEY"
  value = tls_private_key.github_app_private_key.private_key_pem
}

resource "octovault_application_secret" "github_app_public_key_code_scanning" {
  application = "github"
  environment = "${var.stamp_name}"

  key = "APP_PUBLIC_KEY_CODE_SCANNING"
  value = tls_private_key.github_app_private_key.public_key_pem
}
