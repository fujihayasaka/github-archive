// Package cosmos provides a connection to the Cosmos DB.
package cosmos

import (
	"context"
	"errors"
	"net/http"

	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/Azure/azure-sdk-for-go/sdk/azcore/runtime"
	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/Azure/azure-sdk-for-go/sdk/tracing/azotel"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/config"
	"go.opentelemetry.io/otel"
)

// ReadWriter is an interface for reading from a Cosmos DB container.
type ReadWriter interface {
	NewQueryItemsPager(query string, partitionKey azcosmos.PartitionKey, o *azcosmos.QueryOptions) *runtime.Pager[azcosmos.QueryItemsResponse]
	ReadItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	UpsertItem(ctx context.Context, partitionKey azcosmos.PartitionKey, item []byte, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	CreateItem(ctx context.Context, partitionKey azcosmos.PartitionKey, item []byte, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	DeleteItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	PatchItem(ctx context.Context, partitionKey azcosmos.PartitionKey, id string, ops azcosmos.PatchOperations, o *azcosmos.ItemOptions) (azcosmos.ItemResponse, error)
	DatabaseName() string
	ContainerName() string
	NewTransactionalBatch(partitionKey azcosmos.PartitionKey) azcosmos.TransactionalBatch
	ExecuteTransactionalBatch(ctx context.Context, batch azcosmos.TransactionalBatch, o *azcosmos.TransactionalBatchOptions) (azcosmos.TransactionalBatchResponse, error)
}

// DatabaseConnection contains the connection to the Cosmos DB.
type DatabaseConnection struct {
	*azcosmos.ContainerClient
	*azcosmos.DatabaseClient
	Client  *azcosmos.Client
	logger  log.Logger
	statter stats.Client
}

// NewDatabaseConnection creates a new DatabaseConnection.
func NewDatabaseConnection(ctx context.Context, cfg *config.Config, logger log.Logger, statter stats.Client) (*DatabaseConnection, error) {
	options := &azcosmos.ClientOptions{ClientOptions: azcore.ClientOptions{
		TracingProvider: azotel.NewTracingProvider(otel.GetTracerProvider(), nil),
	}}
	client, err := newDatabaseClient(cfg, options)
	if err != nil {
		return nil, err
	}

	if !cfg.IsProduction() {
		// create database if it doesn't exist
		databaseProperties := azcosmos.DatabaseProperties{ID: cfg.DatabaseName}
		_, err = client.CreateDatabase(ctx, databaseProperties, nil)
		if err != nil && !isAzResponseError(err, http.StatusConflict) {
			return nil, err
		}
	}

	database, err := client.NewDatabase(cfg.DatabaseName)
	if err != nil {
		return nil, err
	}

	if !cfg.IsProduction() {
		// create container if it doesn't exist
		defaultTTL := int32(-1) // -1 means TTL is enabled on the container but items don't expire by default
		containerProperties := azcosmos.ContainerProperties{
			ID: cfg.ContainerName,
			PartitionKeyDefinition: azcosmos.PartitionKeyDefinition{
				Paths: []string{"/partitionKey"},
			},
			DefaultTimeToLive: &defaultTTL,
		}
		_, err = database.CreateContainer(ctx, containerProperties, nil)
		if err != nil && !isAzResponseError(err, http.StatusConflict) {
			return nil, err
		}
	}

	container, err := database.NewContainer(cfg.ContainerName)
	if err != nil {
		return nil, err
	}

	logger.Info(
		"Connected to CosmosDB",
		kvp.String("accountEndpoint", client.Endpoint()),
		kvp.String("database", cfg.DatabaseName),
		kvp.String("container", cfg.ContainerName),
	)

	return &DatabaseConnection{
		DatabaseClient:  database,
		ContainerClient: container,
		Client:          client,
		statter:         statter,
		logger:          logger,
	}, nil
}

// DatabaseName returns the name of the database.
func (c *DatabaseConnection) DatabaseName() string {
	return c.DatabaseClient.ID()
}

// ContainerName returns the name of the container.
func (c *DatabaseConnection) ContainerName() string {
	return c.ContainerClient.ID()
}

func newDatabaseClient(cfg *config.Config, opts *azcosmos.ClientOptions) (*azcosmos.Client, error) {
	if !cfg.IsProduction() {
		return azcosmos.NewClientFromConnectionString(cfg.DBConnectionString, opts)
	}

	// Production environment uses RBAC authentication
	if cfg.DBReadWriteSPNTenantID == "" || cfg.DBReadWriteSPNClientID == "" || cfg.DBReadWriteSPNClientSecret == "" {
		return nil, errors.New("missing required Cosmos configuration for production environment, check DB_READ_WRITE_SPN_* environment variables")
	}
	clientSecretCredential, _ := azidentity.NewClientSecretCredential(cfg.DBReadWriteSPNTenantID, cfg.DBReadWriteSPNClientID, cfg.DBReadWriteSPNClientSecret, nil)

	return azcosmos.NewClient(cfg.DatabaseEndpoint, clientSecretCredential, opts)
}

func isAzResponseError(err error, code int) bool {
	var azError *azcore.ResponseError
	return err != nil && errors.As(err, &azError) && azError.StatusCode == code
}

// IsNotFoundError returns true if the error is a 404.
func IsNotFoundError(err error) bool {
	return isAzResponseError(err, http.StatusNotFound)
}

// IsPreconditionFailedError returns true if an operation specified an eTag that doesn't match the one on the server.
func IsPreconditionFailedError(err error) bool {
	return isAzResponseError(err, http.StatusPreconditionFailed)
}

// GetItemResponseLoggerFields returns a list of relevant fields for logging.
func GetItemResponseLoggerFields(itemResponse azcosmos.ItemResponse, timeElapsed time.Duration, err error) []kvp.Field {
	fields := []kvp.Field{
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	}

	if timeElapsed != 0 {
		fields = append(fields, kvp.Int64("db.cosmosdb.time_elapsed", timeElapsed.Milliseconds()))
	}

	if err != nil {
		fields = append(fields, kvp.Int("db.status_code", GetErrorStatusCode(err)))
	} else {
		if itemResponse.RawResponse == nil {
			fields = append(fields, kvp.Int("db.status_code", 0))
		} else {
			fields = append(fields, kvp.Int("db.status_code", itemResponse.RawResponse.StatusCode))
		}
	}

	return fields
}

// Is409Conflict returns true if the error is a 409.
func Is409Conflict(err error) bool {
	return isAzResponseError(err, http.StatusConflict)
}

// Is403Forbidden returns true if the error is a 403.
func Is403Forbidden(err error) bool {
	return isAzResponseError(err, http.StatusForbidden)
}

// AsAzError returns the azcore.ResponseError from the error.
func AsAzError(err error) *azcore.ResponseError {
	var responseErr *azcore.ResponseError
	errors.As(err, &responseErr)
	return responseErr
}

// GetErrorStatusCode returns the status code of the error.
func GetErrorStatusCode(err error) int {
	azError := AsAzError(err)

	if azError != nil {
		return azError.StatusCode
	}

	return 0
}
