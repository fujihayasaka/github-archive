// Package cosmos provides shared Cosmos DB client construction and configuration types.
package cosmos

import (
	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel"
	"github.com/github/sweagentd/internal/azureauth"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"go.opentelemetry.io/otel"
)

// Opts contains configuration options for creating a Cosmos DB client.
type Opts struct {
	ConnectionString         string
	Endpoint                 string
	AzureCosmosDBSPNTenantID string
	AzureCosmosDBSPNClientID string
	Obsv                     observability.Exporters
}

// ContainerOpts contains configuration options for creating a Cosmos DB container client.
type ContainerOpts struct {
	Opts

	DatabaseID  string
	ContainerID string
}

// NewCosmosClient creates a new Cosmos DB client with the provided options.
func NewCosmosClient(opts *Opts) (*azcosmos.Client, error) {
	opt := &azcosmos.ClientOptions{
		EnableContentResponseOnWrite: true, // TODO(colbylwilliams): default is false, reevaluate for production
		ClientOptions: azcore.ClientOptions{
			TracingProvider: azotel.NewTracingProvider(otel.GetTracerProvider(), nil),
		},
	}

	var err error
	var cosmos *azcosmos.Client

	switch {
	case opts.Endpoint != "":
		cred, credErr := azureauth.NewAzureCredential(
			opts.AzureCosmosDBSPNTenantID,
			opts.AzureCosmosDBSPNClientID,
		)
		if credErr != nil {
			return nil, goerrors.Errorf("creating Azure credential for CosmosDB: %w", credErr)
		}
		cosmos, err = azcosmos.NewClient(opts.Endpoint, cred, opt)
		if err != nil {
			return nil, err
		}
	case opts.ConnectionString != "":
		cosmos, err = azcosmos.NewClientFromConnectionString(opts.ConnectionString, opt)
		if err != nil {
			return nil, err
		}
	default:
		return nil, goerrors.New("either endpoint or connectionString must be provided")
	}
	return cosmos, nil
}

// NewCosmosContainerClient creates a new Cosmos DB container client with the provided options.
func NewCosmosContainerClient(opts *ContainerOpts) (*azcosmos.ContainerClient, error) {
	client, err := NewCosmosClient(&opts.Opts)
	if err != nil {
		return nil, err
	}
	if opts.DatabaseID == "" {
		return nil, goerrors.New("database ID cannot be empty")
	}
	if opts.ContainerID == "" {
		return nil, goerrors.New("container ID cannot be empty")
	}

	container, err := client.NewContainer(opts.DatabaseID, opts.ContainerID)
	if err != nil {
		return nil, err
	}

	return container, nil
}
