terraform {
  required_providers {
    tls = {
      source = "hashicorp/tls"
      version = "4.0.5"
    }
    octovault = {
      source  = "terraform.githubapp.com/shared-providers/octovault"
      version = "2.0.5"
    }
  }
}

resource "terraform_data" "key_generation_date" {
  input = var.key_generation_date
}

resource "tls_private_key" "private_key" {
  algorithm = "ED25519"

  lifecycle {
    replace_triggered_by = [terraform_data.key_generation_date]
  }
}

resource "octovault_application_secret" "private_key" {
  application = var.application
  environment = var.env
  key   = "AUTH_PRIVATE_KEY"

  value = tls_private_key.private_key.private_key_pem
}

data "octovault_application_secret" "jwks_private_keys" {
  application = var.application
  environment = var.env
  key         = "AUTH_JWKS_PRIVATE_KEYS"
}

locals {
  jwks_private_keys = split(";", data.octovault_application_secret.jwks_private_keys.value)
  default_key = [tls_private_key.private_key.private_key_pem]
}

resource "octovault_application_secret" "jwks_private_keys" {
  application = var.application
  environment = var.env

  key   = "AUTH_JWKS_PRIVATE_KEYS"

  # breakdown of what is happening here:
  # 1. If there are more than 1 private keys, or if there is 1 private key and it is not empty, then we join all the keys together with a semicolon
  # 2. If there is only 1 private key and it is not empty, then we use that key (the empty check is because split on an empty string returns a list with one empty string)
  # 3. If there are no private keys, then we use the default key that was just generated
  value = length(local.jwks_private_keys) > 1 || (length(local.jwks_private_keys) == 1 && local.jwks_private_keys[0] != "") ? join(";", slice(distinct(concat(local.default_key, local.jwks_private_keys)), 0, min(3, length(distinct(concat(local.default_key, local.jwks_private_keys)))))) : local.default_key[0]
}