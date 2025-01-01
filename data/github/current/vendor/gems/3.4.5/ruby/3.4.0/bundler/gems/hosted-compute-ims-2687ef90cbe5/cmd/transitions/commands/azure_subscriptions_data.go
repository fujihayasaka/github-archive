package commands

import "github.com/github/hosted-compute-ims/internal/models"

// AzureStampSubscriptionConfig represents the configuration for a specific region
type AzureStampSubscriptionConfig struct {
	Subscriptions []models.AzureSubscriptionUpsert `yaml:"subscriptions"`
	AzureLocation string                           `yaml:"azureLocation"`
}

// AzureSubscriptionData is the definitive source of truth for Azure subscriptions.
// it is used by the transition to update the database with the latest subscription data.
// It maps from `environment/stamp` to a list of Azure subscriptions that should be present in the database
// for that stamp.
func GetAzureSubscriptionData() map[string]AzureStampSubscriptionConfig {
	return map[string]AzureStampSubscriptionConfig{
		"dev": {
			AzureLocation: "eastus",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "toinsert-1a2b-3c4d-5e6f-7g8h9i0j1k2l",
					ImageType:          "Customer",
					ResourcesPrefix:    "1234567",
					ImageVersionsLimit: 100,
				},
				{
					SubscriptionId:     "toupdate-1a2b-3c4d-5e6f-7g8h9i0j1k2l",
					ImageType:          "Curated",
					ResourcesPrefix:    "updated-from-file",
					ImageVersionsLimit: 1,
				},
			},
		},
		"prod-ae-01": {
			AzureLocation: "australiaeast",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "3656b8d2-0dd1-4fd7-9e8e-a4ce480f1ea3",
					ImageType:          "Customer",
					ResourcesPrefix:    "591339433",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "f429e0ca-3f4a-4331-a872-2430c7e5a19a",
					ImageType:          "Customer",
					ResourcesPrefix:    "563593663",
					ImageVersionsLimit: 1000,
				},
			},
		},
		"prod-cus-01": {
			AzureLocation: "centralus",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "7c5b256f-048e-4b4d-8930-81183860bd7a",
					ImageType:          "Customer",
					ResourcesPrefix:    "4077141861",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "a7894807-bce6-4ba0-8a9c-aaeee2bb121d",
					ImageType:          "Customer",
					ResourcesPrefix:    "2577473242",
					ImageVersionsLimit: 1000,
				},
			},
		},
		"prod-sdc-01": {
			AzureLocation: "swedencentral",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "f541dd5b-debc-4212-9a24-f03b98ebb113",
					ImageType:          "Customer",
					ResourcesPrefix:    "731452554",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "95014fd0-055c-4eca-b255-bd8740d08f7f",
					ImageType:          "Customer",
					ResourcesPrefix:    "4001574564",
					ImageVersionsLimit: 1000,
				},
			},
		},
		"prod-weu-01": {
			AzureLocation: "northeurope",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "2e29e6a6-601c-4847-9093-2d084c0caad9",
					ImageType:          "Customer",
					ResourcesPrefix:    "2612583608",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "f739d193-fcf6-4ea1-bde7-1ef43edde01f",
					ImageType:          "Customer",
					ResourcesPrefix:    "599714229",
					ImageVersionsLimit: 1000,
				},
			},
		},
		"staff-wus2-01": {
			AzureLocation: "westus2",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "e5b5de1a-b349-4f5d-ba87-b54c4689786a",
					ImageType:          "Customer",
					ResourcesPrefix:    "2699734459",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "c3e67025-0573-4be0-91eb-0fe17c791f7b",
					ImageType:          "Customer",
					ResourcesPrefix:    "2207780268",
					ImageVersionsLimit: 1000,
				},
			},
		},
		"test-cnc-01": {
			AzureLocation: "canadacentral",
			Subscriptions: []models.AzureSubscriptionUpsert{
				{
					SubscriptionId:     "bc754582-ec62-4990-8be2-76cf961f62a1",
					ImageType:          "Customer",
					ResourcesPrefix:    "1871547273",
					ImageVersionsLimit: 1000,
				},
				{
					SubscriptionId:     "f8f6e8bf-f96f-494a-aa33-6c02ab6299bc",
					ImageType:          "Customer",
					ResourcesPrefix:    "635648909",
					ImageVersionsLimit: 1000,
				},
			},
		},
	}
}
