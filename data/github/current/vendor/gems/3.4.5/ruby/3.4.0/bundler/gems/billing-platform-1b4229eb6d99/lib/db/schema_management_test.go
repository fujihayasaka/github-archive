package db

import (
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/stretchr/testify/assert"
)

func Test_GetContainerProperties(t *testing.T) {
	tests := []struct {
		name                    string
		config                  *config.Config
		shouldSetIndexingPolicy bool
	}{
		{
			name: "sets indexing policy in development environment",
			config: &config.Config{
				Environment: "development",
			},
			shouldSetIndexingPolicy: true,
		},
		{
			name: "does not set indexing policy in production environment",
			config: &config.Config{
				Environment: "production",
			},
			shouldSetIndexingPolicy: false,
		},
		{
			name: "does not set indexing policy in Proxima environment",
			config: &config.Config{
				Environment: "prod-weu-01",
			},
			shouldSetIndexingPolicy: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			schemaManagement := NewSchemaManagement(tt.config, &Connection{})
			properties := schemaManagement.GetContainerProperties("test-collection-name")
			assert.Equal(t, properties.ID, "test-collection-name")

			if tt.shouldSetIndexingPolicy {
				assert.NotNil(t, properties.IndexingPolicy)
				assert.Equal(t, properties.IndexingPolicy.IncludedPaths, []azcosmos.IncludedPath{
					{Path: "/*"},
					{Path: "/EntityDetail/OrganizationId/?"},
					{Path: "/EntityDetail/RepositoryId/?"},
				})
				assert.Equal(t, properties.IndexingPolicy.ExcludedPaths, []azcosmos.ExcludedPath{
					{Path: "/_etag/?"},
					{Path: "/Pricing/*"},
					{Path: "/EntityDetail/*"},
					{Path: "/FractionalQuantity/?"},
					{Path: "/UsageAt/?"},
					{Path: "/AppliedCostPerQuantity/?"},
					{Path: "/FullQuantity/?"},
				})
			} else {
				assert.Nil(t, properties.IndexingPolicy)
			}
		})
	}
}
