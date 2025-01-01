package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// CustomerEngine is the engine for customers
type CustomerEngine struct {
	statter      stats.Client
	tracer       trace.Tracer
	dbConnection cosmos.ReadWriter
}

// NewCustomerEngine creates a new CustomerEngine.
func NewCustomerEngine(statter stats.Client, tracer trace.Tracer, dbConnection cosmos.ReadWriter) *CustomerEngine {
	return &CustomerEngine{
		statter:      statter,
		tracer:       tracer,
		dbConnection: dbConnection,
	}
}

// Get looks up a Customer by ID. It returns a not found error if the customer does not exist.
func (ce *CustomerEngine) Get(ctx context.Context, id uint64) (*models.Customer, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerEngine.Get")
	defer sp.End()

	pk := azcosmos.NewPartitionKeyString(models.CustomerPartitionKey)
	itemResponse, err := ce.dbConnection.ReadItem(ctx, pk, strconv.FormatUint(id, 10), nil)

	if err != nil {
		recordError(err, sp)
		return nil, fmt.Errorf("failed to get customer: %w", err)
	}

	var customer models.Customer
	if err := json.Unmarshal(itemResponse.Value, &customer); err != nil {
		recordError(err, sp)
		return nil, fmt.Errorf("failed to unmarshal customer: %w", err)
	}
	return &customer, nil
}

// HasHighWatermarkSDLCLicensing returns true if the customer has high watermark SDLC licensing (they are metered and not on a trial).
func (ce *CustomerEngine) HasHighWatermarkSDLCLicensing(ctx context.Context, id uint64) (bool, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerEngine.HasHighWatermarkSDLCLicensing")
	defer sp.End()

	customer, err := ce.Get(ctx, id)
	if err != nil {
		return false, err
	}

	return customer.HasHighWatermarkSdlcLicensing(), nil
}

// GetAll returns all customers that match the given criteria.
func (ce *CustomerEngine) GetAll(
	ctx context.Context,
	logger log.Logger,
	sdlcLicensingModel *models.SdlcLicensingModel,
	sdlcTrial *bool,
) ([]*models.Customer, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerEngine.GetAll")
	defer sp.End()

	queryString := "select * from c"

	queryOptions := &azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{},
	}

	if sdlcLicensingModel != nil {
		queryString += " where c.sdlcLicensingModel = @sdlcLicensingModel"
		queryOptions.QueryParameters = append(queryOptions.QueryParameters, azcosmos.QueryParameter{
			Name:  "@sdlcLicensingModel",
			Value: sdlcLicensingModel.String(),
		})
	}

	if sdlcTrial != nil {
		if len(queryOptions.QueryParameters) > 0 {
			queryString += " and c.sdlcTrial = @sdlcTrial"
		} else {
			queryString += " where c.sdlcTrial = @sdlcTrial"
		}
		queryOptions.QueryParameters = append(queryOptions.QueryParameters, azcosmos.QueryParameter{
			Name:  "@sdlcTrial",
			Value: *sdlcTrial,
		})
	}

	querier := cosmos.NewQuerier[*models.Customer](ce.dbConnection)

	return querier.ExecuteQuery(ctx, queryString, models.CustomerPartitionKey, queryOptions)
}

// Upsert creates or updates a customer.
func (ce *CustomerEngine) Upsert(ctx context.Context, logger log.Logger, customer *models.Customer, o *azcosmos.ItemOptions) error {
	ctx, sp := ce.tracer.Start(ctx, "CustomerEngine.Upsert")
	defer sp.End()

	marshalled, err := json.Marshal(customer)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to marshal customer: %w", err)
	}

	pk := azcosmos.NewPartitionKeyString(customer.PartitionKey)

	itemResponse, err := ce.dbConnection.UpsertItem(
		ctx,
		pk,
		marshalled,
		o,
	)

	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to upsert customer: %w", err)
	}

	logger.Info("Customer upserted",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
		kvp.String("customer.id", customer.ID),
		kvp.String("customer.sdlc_icensing_model", customer.SdlcLicensingModel.String()),
	)

	return nil
}
