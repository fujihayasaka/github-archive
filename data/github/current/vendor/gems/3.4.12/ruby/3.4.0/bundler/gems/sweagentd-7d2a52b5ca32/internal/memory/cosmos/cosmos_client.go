package cosmos

import (
	"errors"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/sweagentd/internal/observability"
)

type CosmosOpts struct {
	ConnectionString             string
	Endpoint                     string
	AzureCosmosDBSPNTenantID     string
	AzureCosmosDBSPNClientID     string
	AzureCosmosDBSPNClientSecret string
	Obsv                         observability.Exporters
}

type CosmosContainerOpts struct {
	DatabaseID  string
	ContainerID string
	CosmosOpts
}

func NewCosmosClient(opts *CosmosOpts) (*azcosmos.Client, error) {
	opt := &azcosmos.ClientOptions{
		EnableContentResponseOnWrite: true, // TODO(colbylwilliams): default is false, reevaluate for production
	}

	var err error
	var cosmos *azcosmos.Client

	switch {
	case opts.ConnectionString != "":
		cosmos, err = azcosmos.NewClientFromConnectionString(opts.ConnectionString, opt)
		if err != nil {
			return nil, err
		}
	case opts.Endpoint != "":
		if opts.AzureCosmosDBSPNTenantID == "" {
			return nil, errors.New("AzureCosmosDBSPNTenantID cannot be empty when using endpoint authentication")
		}
		if opts.AzureCosmosDBSPNClientID == "" {
			return nil, errors.New("AzureCosmosDBSPNClientID cannot be empty when using endpoint authentication")
		}
		if opts.AzureCosmosDBSPNClientSecret == "" {
			return nil, errors.New("AzureCosmosDBSPNClientSecret cannot be empty when using endpoint authentication")
		}
		cred, err := azidentity.NewClientSecretCredential(opts.AzureCosmosDBSPNTenantID, opts.AzureCosmosDBSPNClientID, opts.AzureCosmosDBSPNClientSecret, nil)
		if err != nil {
			return nil, err
		}
		cosmos, err = azcosmos.NewClient(opts.Endpoint, cred, opt)
		if err != nil {
			return nil, err
		}
	default:
		return nil, errors.New("either endpoint or connectionString must be provided")
	}
	return cosmos, nil
}

func NewCosmosContainerClient(opts *CosmosContainerOpts) (*azcosmos.ContainerClient, error) {
	client, err := NewCosmosClient(&opts.CosmosOpts)
	if err != nil {
		return nil, err
	}
	if opts.DatabaseID == "" {
		return nil, errors.New("database ID cannot be empty")
	}
	if opts.ContainerID == "" {
		return nil, errors.New("container ID cannot be empty")
	}

	container, err := client.NewContainer(opts.DatabaseID, opts.ContainerID)
	if err != nil {
		return nil, err
	}

	return container, nil
}
