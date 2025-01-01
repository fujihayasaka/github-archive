// Package engines is used by the API layer to handle requests and responses.
package engines

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// ProductEnablementEngine is the engine for productEnablements.
type ProductEnablementEngine struct {
	statter      stats.Client
	tracer       trace.Tracer
	dbConnection cosmos.ReadWriter
}

// NewProductEnablementEngine creates a new ProductEnablementEngine.
func NewProductEnablementEngine(statter stats.Client, tracer trace.Tracer, dbConnection cosmos.ReadWriter) *ProductEnablementEngine {
	return &ProductEnablementEngine{
		statter:      statter,
		tracer:       tracer,
		dbConnection: dbConnection,
	}
}

// GetAll returns all productEnablements for a customer.
func (pe *ProductEnablementEngine) GetAll(ctx context.Context, logger log.Logger, customerID uint64) ([]*models.ProductEnablement, error) {
	ctx, sp := pe.tracer.Start(ctx, "ProductEnablementEngine.GetAll")
	defer sp.End()

	pk := models.NewProductEnablementPartitionKey(customerID)
	queryString := "select * from c"

	querier := cosmos.NewQuerier[*models.ProductEnablement](pe.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, nil)
}

// Upsert creates or updates a productEnablement.
func (pe *ProductEnablementEngine) Upsert(ctx context.Context, logger log.Logger, productEnablement *models.ProductEnablement, o *azcosmos.ItemOptions) error {
	ctx, sp := pe.tracer.Start(ctx, "ProductEnablementEngine.Upsert")
	defer sp.End()

	marshalled, err := json.Marshal(productEnablement)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to marshal productEnablement: %w", err)
	}
	pk := azcosmos.NewPartitionKeyString(productEnablement.PartitionKey)

	itemResponse, err := pe.dbConnection.UpsertItem(
		ctx,
		pk,
		marshalled,
		o,
	)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to upsert productEnablement: %w", err)
	}
	logger.Info("ProductEnablement created",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
		kvp.Uint64("gh.product_enablement.customer_id", productEnablement.CustomerID),
		kvp.Uint64("gh.product_enablement.enablement_id", productEnablement.EnablementID),
		kvp.String("gh.product_enablement.enablement_type", productEnablement.EnablementType.String()),
	)
	return nil
}
