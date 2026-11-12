terraform {
  cloud {
    organization = "azure-dsp-dependency-graph-prod"
    hostname     = "terraform.githubapp.com"

    workspaces {
      name = "osslicensecompliance-production"
    }
  }
}

module "stamp" {
  source             = "../_modules/stamp"
  stamp_name         = "production"
  stamp_azure_region = "eastus"
}
