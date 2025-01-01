locals {
  team_prefix         = "licensing"
  region              = "eastus"
  vault_application   = "licensify"
  vault_environment   = "production"
  environment_type    = "production"
  catalog_service     = "licensify"
  data_classification = "confidential"
}

module "rg" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.2.2"

  environment_type = local.environment_type
  stamp            = var.stamp_name
  catalog_service  = local.catalog_service

  name_override = var.rg_name_override
  team_prefix   = local.team_prefix
  region        = local.region
}

module "cosmos" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm"
  version = "0.2.2"

  providers = {
    azurerm   = azurerm
    octovault = octovault
  }

  primary_region     = var.primary_regions[var.stamp_name]
  additional_regions = var.secondary_regions[var.stamp_name]

  environment_type    = local.environment_type
  stamp               = var.stamp_name
  catalog_service     = local.catalog_service
  data_classification = local.data_classification

  /*
    This uses the Octovault provider to automatically write Cosmos primary and secondary
    write and read keys to your vault. You will need to have a VAULT_TOKEN environment
    variable configured in your runtime environment with a valid vault access token to
    work. Additionally, if you are running on a local machine, you will need to be on the
    Dev VPN in order to access the vault.
  */
  write_db_secrets_to_vault = true
  vault_details = {
    application_name                                   = var.vault_application
    environment                                        = var.vault_environment
    db_primary_no_sql_connection_string_vault_key_name = "DB_CONNECTION_STR"
  }

  # Used to help generate a database name, if no name is provided
  team_prefix = local.team_prefix
  resource_group = {
    name = module.rg.rg_name
    id   = module.rg.rg_id
  }

  cosmos_account_name_override = var.cosmos_account_name_override

  # Enabled access from Moda IP ranges and Azure portal
  allow_gh_dcs       = var.allow_gh_dcs
  allow_azure_portal = true
  cosmos_flavor      = "SQL"

  # WARNING: THIS SETTING WILL DISABLE TOKEN BASED (LOCAL) AUTHENTICATION. DATA QUERYING VIA
  # AZURE DATA EXPLORER REQUIRES TOKEN BASED (LOCAL) AUTHENTICATION TO BE ENABLED!
  # YOU WILL NOT BE ABLE TO QUERY YOUR DATA IN AZURE IF YOU LEAVE `enabled_key_based_authentication` TO
  # `false`!
  # REVIEW https://github.com/github/CosmosDB/discussions/143 FOR GUIDANCE FOR ON HOW TO BEST CONFIGURE
  # YOUR COSMOS DB RESOURCES TO FIT YOUR LOCAL QUERYING NEEDS.
  enable_key_based_authentication = false

  backup_policy = {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 10
    storage_redundancy  = "Geo"
  }

  sql_databases = [{
    name = "licensify"
    autoscale_settings = {
      max_throughput = 100000
    }
  }]
}
