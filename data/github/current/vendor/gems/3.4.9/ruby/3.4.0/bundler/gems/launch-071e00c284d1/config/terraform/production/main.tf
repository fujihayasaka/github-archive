terraform {
  backend "remote" {
    hostname     = "terraform.githubapp.com"
    organization = "azure-launch"

    workspaces {
      name = "launch-prod-dotcom"
    }
  }
}

locals {
  team_prefix       = "launch"
  catalog_service   = "launch"

  # Lab uses "lab" instead of a stamp name, so it's safe to use "dotcom" for production
  stamp             = "dotcom"

  # A resource group name should be unique per environment as multiple environments could use the same regions
  rg_prefix = "rg-${local.team_prefix}-${local.stamp}-"

  # Storage accounts need to be globally unique
  # They can't contain `-`, so ensure the environment specifier does not include one
  # They must be composed of lowercase letters and numbers with a length between 3 and 24 characters.
  # https://learn.microsoft.com/en-us/azure/azure-resource-manager/troubleshooting/error-storage-account-name?tabs=bicep#account-name-invalid
  sa_prefix = "${local.team_prefix}${local.stamp}sa"

  # TF will always pull the SPN from the production vault environment
  vault_application = "launch"
  vault_environment = "production"

  resource_groups = [
    for region, storage_indexes in var.storage_account_regions : {
        name = "${local.rg_prefix}${region}"
        location = region
        storage_indexes = storage_indexes
        tags = {
          "catalog_service": local.catalog_service,
          "stamp": local.stamp,
        },
    }
  ]

  # flat map of all storage accounts across resource groups
  storage_accounts_unsorted = flatten([
    for rg in local.resource_groups : [
      for idx in rg.storage_indexes : {
        name = "${local.sa_prefix}${idx}"

        resource_group_name = rg.name
        location = rg.location

        index = idx
      }
    ]
  ])
  storage_accounts = { for sa in local.storage_accounts_unsorted : sa.index => sa }
}

provider "octovault" {}

data "octovault_application_secret" "service_principal_client_secret" {
  application = local.vault_application
  environment = local.vault_environment
  key         = "spn_launch_tf"
}

data "octovault_application_secret" "service_principal_client_id" {
  application = local.vault_application
  environment = local.vault_environment
  key         = "spn_launch_tf_client_id"
}

data "octovault_application_secret" "service_principal_tenant_id" {
  application = local.vault_application
  environment = local.vault_environment
  key         = "spn_launch_tf_tenant_id"
}

provider "azurerm" {
  features {}
  client_secret         = data.octovault_application_secret.service_principal_client_secret.value
  tenant_id             = data.octovault_application_secret.service_principal_tenant_id.value
  client_id             = data.octovault_application_secret.service_principal_client_id.value
  subscription_id       = "380b7bd4-a93e-4619-a732-ee564febbf46"

  # By default we discourage the usage of shared keys, if they are disabled we need to instructed
  # the provider to use the Azure AD authentication method.
  storage_use_azuread   = true
}

// Create a Resource Group for each storage account
resource "azurerm_resource_group" "rg" {
  count = length(local.resource_groups)

  name     = local.resource_groups[count.index].name
  location = local.resource_groups[count.index].location
  tags     = local.resource_groups[count.index].tags
}

/*
The following will create an Azure Blob Storage account with the following default configurations:
- account_kind = "StorageV2"
- account_tier = "Standard"
- account_replication_type = "GZRS"
- account_access_tier = "Hot"
*/
module "storage_account" {
  count = length(local.storage_accounts)

  source = "terraform.githubapp.com/azure-object-storage/github-blob-storage/azurerm"
  version = "0.0.6"

  resource_group = {
    name = local.storage_accounts[count.index].resource_group_name
    id   = tolist(toset([for rg in azurerm_resource_group.rg: rg.id if rg.name == local.storage_accounts[count.index].resource_group_name]))[0]
  }

  location = local.storage_accounts[count.index].location

  storage_account_name_override = local.storage_accounts[count.index].name

  team_prefix    = local.team_prefix

  catalog_service = local.catalog_service

  # Workflow payloads contain customer data
  # https://thehub.github.com/security/policy-desk/standards/data-classification-standard/
  data_classification = "restricted"

  storage_container_names = ["payloads"]

  /*
  By default we provide guidance for using Private Links for accessing your ABS
  accounts and denying access by default to the storage account. But by configuring
  `allow_gh_dcs` to `true`, you will be allowing access to the ABS account from our DCs.
  This can be useful for Dotcom in case of incidents where we want to MANUALLY fallback to using 
  the internet instead of routing traffic internally through ExpressRoute and Private Links.
  For Proxima this is not required.

  For more information about the ABS Network path, please visit the documentation
  */
  allow_gh_dcs = true

  blob_properties = {
    "container_delete_retention_policy": {
      "days": 15
    },
    "delete_retention_policy": {
      "days": 15
    },
    "versioning_enabled": true,
  }
}

// Set up a blob retention policy for each storage account
resource "azurerm_storage_management_policy" "blob_retention" {
  count = length(local.storage_accounts)
  storage_account_id = tolist([for sa in module.storage_account: sa.storage_account_id if sa.storage_account_name == local.storage_accounts[count.index].name])[0]

  rule {
    name    = "blob_retention_policy"
    enabled = true
    filters {
      blob_types   = ["blockBlob", "appendBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_creation_greater_than = 40
      }
    }
  }
}