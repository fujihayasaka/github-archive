// Package testcontainer provides utilities for testing with Cosmos DB using Testcontainers.
package testcontainer

import (
	"fmt"
	"os"
	"strconv"
	"testing"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/wait"
)

// CosmosTestContainer is a wrapper around a Cosmos DB test container.
// It provides methods to create a new Cosmos client for testing purposes.
type CosmosTestContainer struct {
	container       testcontainers.Container
	containerClient *azcosmos.ContainerClient
}

// NewCosmosTestContainer creates a new CosmosTestContainer for testing.
func NewCosmosTestContainer(t *testing.T) *CosmosTestContainer {
	enableTest, _ := strconv.ParseBool(os.Getenv("RUN_INTEGRATION_TESTS"))
	if !enableTest {
		t.Skip("Skipping Cosmos DB test because RUN_INTEGRATION_TESTS is not set")
	}
	container := newTestContainer(t)
	return &CosmosTestContainer{
		container:       container,
		containerClient: newCosmosDatabaseContainerClient(t, container),
	}
}

// Client returns the Cosmos DB client for the test container.
func (c *CosmosTestContainer) Client() *azcosmos.ContainerClient {
	return c.containerClient
}

func newCosmosDatabaseContainerClient(t *testing.T, container testcontainers.Container) *azcosmos.ContainerClient {
	ctx := t.Context()
	port, err := container.MappedPort(t.Context(), "8081/tcp")
	require.NoError(t, err, "Failed to get mapped port for Cosmos container")
	// Credentials for the Cosmos DB emulator
	// These credentials are used for the local emulator
	// For production, use environment variables or secure vaults to manage credentials.
	// See: https://learn.microsoft.com/en-us/azure/cosmos-db/local-emulator#connect-to-the-emulator
	credentials, err := azcosmos.NewKeyCredential("C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==")
	require.NoError(t, err, "Failed to create Cosmos key credential")

	cosmosClient, err := azcosmos.NewClientWithKey(fmt.Sprintf("http://localhost:%d/", port.Int()), credentials, nil)
	require.NoError(t, err, "Failed to create Cosmos client")

	_, err = cosmosClient.CreateDatabase(ctx, azcosmos.DatabaseProperties{
		ID: "testdb",
	}, &azcosmos.CreateDatabaseOptions{})
	require.NoError(t, err, "Failed to create test database client")
	database, err := cosmosClient.NewDatabase("testdb")
	require.NoError(t, err, "Failed to create test database client")
	_, err = database.CreateContainer(ctx, azcosmos.ContainerProperties{
		PartitionKeyDefinition: azcosmos.PartitionKeyDefinition{
			Paths: []string{"/partition_key"},
		},
		ID: "testcontainer",
	}, &azcosmos.CreateContainerOptions{})
	require.NoError(t, err, "Failed to create test database")
	containerClient, err := cosmosClient.NewContainer("testdb", "testcontainer")
	require.NoError(t, err, "Failed to create test container client")
	return containerClient
}

func newTestContainer(t *testing.T) testcontainers.Container {
	ctx := t.Context()
	req := testcontainers.ContainerRequest{
		Image:        "mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview",
		ExposedPorts: []string{"8081:8081/tcp", "1234/tcp"},
		WaitingFor:   wait.ForExposedPort(),
		Cmd:          []string{"--protocol", "http"},
	}
	container, err := testcontainers.GenericContainer(ctx, testcontainers.GenericContainerRequest{
		ContainerRequest: req,
		Started:          true,
	})
	require.NoError(t, err)
	t.Cleanup(func() {
		testcontainers.CleanupContainer(t, container)
	})
	return container
}
