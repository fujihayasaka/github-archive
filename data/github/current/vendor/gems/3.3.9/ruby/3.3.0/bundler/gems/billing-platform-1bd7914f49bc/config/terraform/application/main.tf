module "rg" {
  count   = var.create_rg ? 1 : 0
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm//modules/azure-resource-group"
  version = "0.1.1" # Be sure to use the latest version you can

  team_prefix   = local.team_prefix
  region        = var.primary_regions[var.stamp_name].location
  name_override = var.rg_name_override
}

data "azurerm_resource_group" "rg_lookup" {
  count = var.create_rg ? 0 : 1
  name  = var.rg_name_override
}

module "cosmos" {
  source  = "terraform.githubapp.com/azure-data-patterns-and-scaling/github-cosmos/azurerm"
  version = "0.1.1" # Be sure to use the latest version you can

  enable_automatic_failover = var.automatic_failover_enabled

  providers = {
    azurerm   = azurerm
    octovault = octovault
  }

  /*
    This uses the Octovault provider to automatically write Cosmos primary and secondary
    write and read keys to your vault. You will need to have a VAULT_TOKEN environment
    variable configured in your runtime environment with a valid vault access token to
    work. Additionally, if you are running on a local machine, you will need to be on the
    Dev VPN in order to access the vault.
  */
  write_db_secrets_to_vault = var.write_db_secrets_to_vault
  vault_details = {
    application_name                                   = local.vault_application
    environment                                        = var.vault_environment
    db_primary_no_sql_connection_string_vault_key_name = "COSMOS_CONN_STR"
  }

  # Used to help generate a database name, if no name is provided
  team_prefix = local.team_prefix
  resource_group = {
    name = var.create_rg ? module.rg[0].rg_name : data.azurerm_resource_group.rg_lookup[0].name
    id   = var.create_rg ? module.rg[0].rg_id : data.azurerm_resource_group.rg_lookup[0].id
  }

  # Enables access from Moda IP ranges
  allow_gh_dcs  = var.allow_gh_dcs
  cosmos_flavor = "SQL"
  additional_ips_to_allow = var.additional_ips

  primary_region     = var.primary_regions[var.stamp_name]
  additional_regions = var.secondary_regions[var.stamp_name]

  # This is an example backup policy. Consult the detailed configuration docs for more
  # info on how to configure this.
  backup_policy = {
    type                = "Periodic"
    interval_in_minutes = 240
    retention_in_hours  = 8
    storage_redundancy  = "Geo"
  }

  cosmos_account_name_override = var.cosmos_account_name

  consistency_policy = {
    consistency_level = "Session"
  }

  additional_tags = var.additional_tags
}

resource "azurerm_cosmosdb_sql_database" "billing-database" {
  resource_group_name = var.create_rg ? module.rg[0].rg_name : data.azurerm_resource_group.rg_lookup[0].name
  account_name        = module.cosmos.db_account_name
  name                = "billing-platform"

  dynamic "autoscale_settings" {
    for_each = var.database_autoscale_max_throughput != null ? [1] : []
    content {
      max_throughput = var.database_autoscale_max_throughput
    }
  }
}

resource "azurerm_cosmosdb_sql_container" "billing-container" {
  resource_group_name = var.create_rg ? module.rg[0].rg_name : data.azurerm_resource_group.rg_lookup[0].name
  account_name        = module.cosmos.db_account_name
  database_name       = azurerm_cosmosdb_sql_database.billing-database.name

  name                = "billing-platform-v2"
  partition_key_paths = ["/partitionKey"]
  partition_key_version = 2

  conflict_resolution_policy {
    conflict_resolution_path = "/_ts"
    mode = "LastWriterWins"
  }

  indexing_policy {
    indexing_mode = "consistent"

    included_path {
      path = "/*"
    }
    included_path {
      path = "/EntityDetail/OrganizationId/?"
    }
    included_path {
      path = "/EntityDetail/RepositoryId/?"
    }

    excluded_path {
      path = "/_etag/?"
    }
    excluded_path {
      path = "/Pricing/*"
    }
    excluded_path {
      path = "/EntityDetail/*"
    }
    excluded_path {
      path = "/FractionalQuantity/?"
    }
    excluded_path {
      path = "/UsageAt/?"
    }
    excluded_path {
      path = "/AppliedCostPerQuantity/?"
    }
    excluded_path {
      path = "/FullQuantity/?"
    }
  }
}
