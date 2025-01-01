package db

import (
	"context"
	_ "embed"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/billing-platform/lib/config"
	"github.com/github/billing-platform/lib/rest"
	"github.com/pkg/errors"
)

//go:embed cosmos/serverSide/triggers/budget.js
var budgetTrigger string

type SchemaManagement struct {
	dbClient     *azcosmos.DatabaseClient
	client       *azcosmos.Client
	isProduction bool
	cfg          *config.Config
}

func NewSchemaManagement(cfg *config.Config, connection *Connection) *SchemaManagement {
	return &SchemaManagement{
		dbClient:     connection.DatabaseClient,
		client:       connection.Client,
		isProduction: cfg.IsProduction(),
		cfg:          cfg,
	}
}

// CreateDatabase creates a database in the cosmos account in scope
// if the database already exists, it will not error
func (h *SchemaManagement) CreateDatabase(ctx context.Context, name string) error {
	properties := azcosmos.DatabaseProperties{
		ID: name,
	}
	throughPutProperties := azcosmos.NewManualThroughputProperties(10000)
	createOptions := &azcosmos.CreateDatabaseOptions{
		ThroughputProperties: &throughPutProperties,
	}
	_, err := h.client.CreateDatabase(ctx, properties, createOptions)
	if err != nil {
		if !Is409Conflict(err) {
			return errors.Wrap(err, "failed to create database")
		}
	}

	return nil
}

func (h *SchemaManagement) RemoveDatabase(ctx context.Context, databaseName string) error {
	if h.isProduction {
		return fmt.Errorf("cannot delete database in production")
	}

	database, err := h.client.NewDatabase(databaseName)
	if err != nil {
		return errors.Wrap(err, "failed to initialize database")
	}

	if _, err := database.Delete(ctx, nil); err != nil {
		return errors.Wrap(err, "failed to delete database")
	}

	return nil
}

// CreateCollection creates a collection in the database in scope
// if the collection already exists, it will not error
func (h *SchemaManagement) CreateCollection(ctx context.Context, name string) error {
	if _, err := h.dbClient.CreateContainer(ctx, h.GetContainerProperties(name), nil); err != nil {
		if !Is409Conflict(err) {
			return errors.Wrap(err, "failed to create container")
		}
	}

	return nil
}

func (h *SchemaManagement) GetContainerProperties(name string) azcosmos.ContainerProperties {
	properties := azcosmos.ContainerProperties{
		ID: name,
		PartitionKeyDefinition: azcosmos.PartitionKeyDefinition{
			Paths:   []string{"/partitionKey"},
			Version: 2,
		},
	}

	// Only apply indexing policy to dev containers as the production indexing policy should be managed and applied via Terraform
	if !h.isProduction {
		properties.IndexingPolicy = &azcosmos.IndexingPolicy{
			IndexingMode: azcosmos.IndexingModeConsistent,
			Automatic:    true,
			IncludedPaths: []azcosmos.IncludedPath{
				{Path: "/*"},
				{Path: "/EntityDetail/OrganizationId/?"},
				{Path: "/EntityDetail/RepositoryId/?"},
			},
			ExcludedPaths: []azcosmos.ExcludedPath{
				{Path: "/_etag/?"},
				{Path: "/Pricing/*"},
				{Path: "/EntityDetail/*"},
				{Path: "/FractionalQuantity/?"},
				{Path: "/UsageAt/?"},
				{Path: "/AppliedCostPerQuantity/?"},
				{Path: "/FullQuantity/?"},
			},
		}
	}

	return properties
}

// RemoveCollection removes a collection from the database in scope
func (h *SchemaManagement) RemoveCollection(ctx context.Context, collectionName string) error {
	if h.isProduction {
		return fmt.Errorf("cannot delete collection in production")
	}

	container, err := h.dbClient.NewContainer(collectionName)
	if err != nil {
		return errors.Wrap(err, "failed to initialize container")
	}

	if _, err := container.Delete(ctx, nil); err != nil {
		return errors.Wrap(err, "failed to delete container")
	}

	return nil
}

func (h *SchemaManagement) EnsureDatabaseExists(ctx context.Context, databaseName string) error {
	if h.client != nil && databaseName != "" {
		if err := h.CreateDatabase(ctx, databaseName); err != nil {
			return err
		}

		dbClient, err := h.client.NewDatabase(databaseName)
		if err != nil {
			return errors.Wrap(err, "failed to initialize database")
		}

		h.dbClient = dbClient
	}

	return nil
}

func (h *SchemaManagement) EnsureCollectionExists(ctx context.Context, collectionName string) error {
	return h.EnsureCollectionAndDatabaseExists(ctx, collectionName, h.cfg.DatabaseName)
}

func (h *SchemaManagement) EnsureCollectionAndDatabaseExists(ctx context.Context, collectionName, databaseName string) error {
	if err := h.EnsureDatabaseExists(ctx, databaseName); err != nil {
		return err
	}

	if err := h.CreateCollection(ctx, collectionName); err != nil {
		return err
	}

	// TODO: generalize this if/when we have more than one trigger
	// files, err := os.ReadDir(h.cfg.TriggerFilePath)
	// if err != nil {
	// 	return err
	// }
	// for _, file := range files {
	// 	fmt.Println(file.Name(), file.IsDir())

	var triggers []*rest.CosmosTrigger
	var returnError error
	for i := 0; i < 3; i++ {
		returnError = nil

		var err error
		triggers, err = rest.GetTriggers(h.cfg, databaseName, collectionName)
		if err == nil {
			break
		}
		if !Is403Forbidden(err) {
			return err
		}

		returnError = err
	}

	if returnError != nil {
		return returnError
	}

	budgetExists := triggerExists(triggers, "budget")
	for i := 0; i < 3; i++ {
		returnError = nil

		err := rest.CreateOrUpdateTrigger(h.cfg, databaseName, collectionName, "budget", "All", "Post", budgetExists, budgetTrigger)
		if err == nil {
			break
		}
		if !Is403Forbidden(err) {
			return err
		}

		returnError = err
	}

	return returnError
}

func triggerExists(triggers []*rest.CosmosTrigger, triggerName string) bool {
	for _, trigger := range triggers {
		if trigger.Id == triggerName {
			return true
		}
	}
	return false
}
