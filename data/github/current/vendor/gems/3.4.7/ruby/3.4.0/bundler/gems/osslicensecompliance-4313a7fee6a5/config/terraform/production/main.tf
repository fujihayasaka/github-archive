terraform {
  cloud {
    organization = "azure-dsp-dependency-graph-prod"
    hostname     = "terraform.githubapp.com"

    workspaces {
      name = "osslicensecompliance-production"
    }
  }
}

module "secrets" {
  source = "../_modules/secrets"
}

module "stamp" {
  source             = "../_modules/stamp"
  stamp_name         = "production"
  stamp_azure_region = "eastus"
}
