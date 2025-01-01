package db

import (
	"net/http"
	"strings"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel"
	"github.com/github/billing-platform/lib/config"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel"
)

// Connection represents a connection to the Cosmos database and container.
//
// Embeds Cosmos ContainerClient allowing:
//
//	change througput, read, update, and delete operations on the container.
//
// Embeds Cosmos Client allowing interaction with the Azure Cosmos DB service
// Embeds Cosmos DatabaseClient allowing:
//
//	create, delete, read, and list operations on databases
type Connection struct {
	// https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos#ContainerClient
	*azcosmos.ContainerClient
	// https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos#Client
	Client *azcosmos.Client
	// https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos#DatabaseClient
	DatabaseClient *azcosmos.DatabaseClient
}

// newDBConnection creates a new connection to the database and container
// specified in the config.
func NewDBConnections(cfg *config.Config) (*Connection, *Connection, error) {
	conn, gatewayConn, err := newConnections(cfg)
	if err != nil {
		return nil, nil, err
	}
	return conn, gatewayConn, nil
}

func newCosmosClient(accountKey, sdkURI string) (*azcosmos.Client, error) {
	cred, err := azcosmos.NewKeyCredential(accountKey)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create cosmos key credential")
	}

	// https://pkg.go.dev/github.com/Azure/azure-sdk-for-go/sdk/azcore@v1.14.0/policy#ClientOptions
	options := &azcosmos.ClientOptions{ClientOptions: azcore.ClientOptions{
		TracingProvider: azotel.NewTracingProvider(otel.GetTracerProvider(), nil),
	}}
	client, err := azcosmos.NewClientWithKey(sdkURI, cred, options)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create cosmos client")
	}

	return client, nil
}

func newConnection(accountKey, sdkURI, dbName, containerName string) (*Connection, error) {
	client, err := newCosmosClient(accountKey, sdkURI)
	if err != nil {
		return nil, errors.Wrap(err, "failed to create Cosmos client")
	}

	database, err := client.NewDatabase(dbName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos database")
	}

	container, err := database.NewContainer(containerName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos container")
	}

	return &Connection{
		ContainerClient: container,
		Client:          client,
		DatabaseClient:  database,
	}, nil
}

func newRBACConnection(cfg *config.Config, readOnly bool, useDedicatedGateway bool) (*Connection, error) {
	var tenantID, clientID, clientSecret, accountEndpoint string

	if readOnly {
		tenantID = cfg.DBReadOnlySPNTenantID
		clientID = cfg.DBReadOnlySPNClientID
		clientSecret = cfg.DBReadOnlySPNClientSecret
	}

	// TODO: Implementation for read/write connections will be added later
	// See: https://github.com/github/billing-platform/pull/2052

	if useDedicatedGateway {
		// https://learn.microsoft.com/en-us/azure/cosmos-db/how-to-configure-integrated-cache?tabs=dotnet#authenticate-with-role-based-access-control
		accountEndpoint = strings.Replace(cfg.CosmosAccountEndpoint, "documents.azure.com", "sqlx.cosmos.azure.com", 1)
	} else {
		accountEndpoint = cfg.CosmosAccountEndpoint
	}

	cc, _ := azidentity.NewClientSecretCredential(tenantID, clientID, clientSecret, nil)

	options := &azcosmos.ClientOptions{ClientOptions: azcore.ClientOptions{
		TracingProvider: azotel.NewTracingProvider(otel.GetTracerProvider(), nil),
	}}

	client, err := azcosmos.NewClient(accountEndpoint, cc, options)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos client")
	}

	database, err := client.NewDatabase(cfg.DatabaseName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos database")
	}

	container, err := database.NewContainer(cfg.ContainerName)
	if err != nil {
		return nil, errors.Wrap(err, "failed to initialize Cosmos container")
	}

	return &Connection{
		ContainerClient: container,
		Client:          client,
		DatabaseClient:  database,
	}, nil
}

func newConnections(cfg *config.Config) (*Connection, *Connection, error) {
	if cfg.IsLocal() {
		return nil, nil, nil
	}

	sdkURI := cfg.DatabaseEndPoint
	accountKey := cfg.DatabaseKey

	defaultConnection, err := newConnection(accountKey, sdkURI, cfg.DatabaseName, cfg.ContainerName)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to initialize the default connection")
	}

	gatewaySdkURI := cfg.GatewayDatabaseEndPoint
	gatewayAccountKey := cfg.GatewayDatabaseKey

	gatewayConnection, err := newConnection(gatewayAccountKey, gatewaySdkURI, cfg.DatabaseName, cfg.ContainerName)
	if err != nil {
		return nil, nil, errors.Wrap(err, "failed to initialize the gateway connection")
	}

	return defaultConnection, gatewayConnection, nil
}

func AsAzError(err error) *azcore.ResponseError {
	var responseErr *azcore.ResponseError
	errors.As(err, &responseErr)
	return responseErr
}

func Is409Conflict(err error) bool {
	if err == nil {
		return false
	}

	azErr := AsAzError(err)
	return azErr != nil && azErr.StatusCode == 409
}

func Is403Forbidden(err error) bool {
	if err == nil {
		return false
	}

	azErr := AsAzError(err)
	return azErr != nil && azErr.StatusCode == 403
}

func Is429ToManyRequests(err error) bool {
	if err == nil {
		return false
	}

	azErr := AsAzError(err)
	return azErr != nil && azErr.StatusCode == 429
}

func Is404NotFound(err error) bool {
	if err == nil {
		return false
	}

	azErr := AsAzError(err)
	// cosmos returns 404 as error. We are fine if its not found
	return azErr != nil && azErr.StatusCode == 404
}

func Is412PreconditionError(err error) bool {
	if err == nil {
		return false
	}

	azErr := AsAzError(err)
	// 412 status code for pre condition failures
	return azErr != nil && azErr.StatusCode == http.StatusPreconditionFailed
}
