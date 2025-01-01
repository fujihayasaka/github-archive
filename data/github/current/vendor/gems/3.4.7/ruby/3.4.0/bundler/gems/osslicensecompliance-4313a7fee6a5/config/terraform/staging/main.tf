terraform {
  cloud {
    organization = "azure-dsp-dependency-graph-prod"
    hostname     = "terraform.githubapp.com"

    workspaces {
      name = "osslicensecompliance-staging"
    }
  }
}

module "secrets" {
  source = "../_modules/secrets"
}

module "stamp" {
  source             = "../_modules/stamp"
  stamp_name         = "staging"
  stamp_azure_region = "eastus"
}
