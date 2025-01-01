terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-hosted-compute"
    workspaces {
      prefix = "hosted_compute_ims_"
    }
  }
}

locals {
  team_prefix = "hosted-compute"
  environments = var.environments
}

module "auth" {
  for_each = local.environments

  source = "../modules/auth"

  application = "hosted-compute-ims"
  env         = each.key
  key_generation_date = each.value.key_keeper_date
}
