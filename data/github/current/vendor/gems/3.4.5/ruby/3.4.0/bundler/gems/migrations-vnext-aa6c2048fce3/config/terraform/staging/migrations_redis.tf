resource "azurerm_redis_cache" "migrations_vnext_cache" {
  name                = "mvn-redis-${var.env}"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  # 13G cache size, high perf network
  capacity            = 2
  family              = "P"
  sku_name            = "Premium"
  minimum_tls_version = "1.2"
  # There is an ongoing issue with building redis with zone redundancy
  #zones = ["1", "2", "3"]
  replicas_per_master           = 1
  public_network_access_enabled = false

  tags = var.tags
}


# store redis connection info in vault for sites-api to use
resource "octovault_application_secret" "migrations_vnext_cache_url" {
  application = var.vaultapp
  environment = var.vaultenv
  key         = "AZURE_REDIS_URL"
  value       = "rediss://${azurerm_redis_cache.migrations_vnext_cache.hostname}:${azurerm_redis_cache.migrations_vnext_cache.ssl_port}"
}

resource "octovault_application_secret" "migrations_vnext_cache_key" {
  application = var.vaultapp
  environment = var.vaultenv
  key         = "AZURE_REDIS_KEY"
  value       = azurerm_redis_cache.migrations_vnext_cache.primary_access_key
}


# Create the firewall rules to allow us access from internal ips
# The `azurerm_redis_firewall_rule` does not take a range so
# these are hard coded to our ip addresses
resource "azurerm_redis_firewall_rule" "GitHubNetwork1" {
  name                = "allow_gh_services_1"
  resource_group_name = azurerm_resource_group.rg.name
  redis_cache_name    = azurerm_redis_cache.migrations_vnext_cache.name
  start_ip            = "140.82.112.0"
  end_ip              = "140.82.127.255"
}

resource "azurerm_redis_firewall_rule" "GitHubNetwork2" {
  name                = "allow_gh_services_2"
  resource_group_name = azurerm_resource_group.rg.name
  redis_cache_name    = azurerm_redis_cache.migrations_vnext_cache.name
  start_ip            = "192.30.252.0"
  end_ip              = "192.30.255.255"
}

resource "azurerm_redis_firewall_rule" "GitHubNetwork3" {
  name                = "allow_gh_services_3"
  resource_group_name = azurerm_resource_group.rg.name
  redis_cache_name    = azurerm_redis_cache.migrations_vnext_cache.name
  start_ip            = "185.199.108.0"
  end_ip              = "185.199.111.255"
}

resource "azurerm_redis_firewall_rule" "GitHubNetwork4" {
  name                = "allow_gh_services_4"
  resource_group_name = azurerm_resource_group.rg.name
  redis_cache_name    = azurerm_redis_cache.migrations_vnext_cache.name
  start_ip            = "143.55.64.0"
  end_ip              = "143.55.79.255"
}