package resources

type Config struct {
	AzureImageLocation                 string   `config:"eastus,env=AZURE_IMAGE_LOCATION"`
	CustomImageAzureRegions            []string `config:"eastus westus2,env=CUSTOM_IMAGE_AZURE_REGIONS"`
	CuratedImageAzureRegions           []string `config:"eastus westus2,env=CURATED_IMAGE_AZURE_REGIONS"`
	MaxImageDefinitionsPerSubscription int      `config:"50,env=MAX_IMAGE_DEFINITIONS_PER_SUBSCRIPTION"`
	MaxSubscriptionsToQueryInDb        int      `config:"10,env=MAX_SUBSCRIPTIONS_TO_QUERY_IN_DB"`
	DeveloperId                        string   `config:",env=GITHUB_USER"` // GITHUB_USER env variable is already set in codespace environment
}
