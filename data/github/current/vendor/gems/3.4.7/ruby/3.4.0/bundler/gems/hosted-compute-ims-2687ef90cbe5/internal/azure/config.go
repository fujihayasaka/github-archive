package azure

// Azure Service Principal settings are used as credentials for connecting to IMS managed subscriptions and blob storage
type Config struct {
	AzureClientID     string `config:",env=SPN_HOSTED_COMPUTE_IMS_CLIENT_ID"`
	AzureTenantID     string `config:",env=SPN_HOSTED_COMPUTE_IMS_TENANT_ID"`
	AzureClientSecret string `config:",env=SPN_HOSTED_COMPUTE_IMS"`
}
