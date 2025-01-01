terraform {
  required_version = ">= 0.14.6"
  required_providers {
    octovault = {
      source = "terraform.githubapp.com/shared-providers/octovault"
      version = ">= 2.0.0"
    }
  }
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-dsp-code-scanning-experiences-prod"
    workspaces {
      name = "turboghas-prod-ae-01"
    }
  }
}

module "secrets" {
  source = "../_modules/secrets"
}

module "stamp" {
  source = "../_modules/stamp"
  stamp_name = "prod-ae-01"
}
