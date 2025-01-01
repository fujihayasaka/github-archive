package engines

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"
)

// CustomerLicenseEngine is the engine for customerLicenses.
type CustomerLicenseEngine struct {
	statter      stats.Client
	tracer       trace.Tracer
	dbConnection cosmos.ReadWriter
}

// NewCustomerLicenseEngine creates a new CustomerLicenseEngine.
func NewCustomerLicenseEngine(statter stats.Client, tracer trace.Tracer, dbConnection cosmos.ReadWriter) *CustomerLicenseEngine {
	return &CustomerLicenseEngine{
		statter:      statter,
		tracer:       tracer,
		dbConnection: dbConnection,
	}
}

// Get looks up a CustomerLicense by partition Key and ID. It returns nil if the CustomerLicense is not found.
func (ce *CustomerLicenseEngine) Get(ctx context.Context, key models.Key) (*models.CustomerLicense, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.Get")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := ce.dbConnection.ReadItem(ctx, pk, key.ID, nil)
	if err != nil {
		if cosmos.IsNotFoundError(err) {
			return nil, nil
		}
		recordError(err, sp)
		return nil, fmt.Errorf("failed to get customerLicense: %w", err)
	}
	var cl models.CustomerLicense
	if err := json.Unmarshal(itemResponse.Value, &cl); err != nil {
		recordError(err, sp)
		return nil, fmt.Errorf("failed to unmarshal customerLicense: %w", err)
	}
	return &cl, nil
}

// GetAll returns all customerLicenses for a customer and product.
func (ce *CustomerLicenseEngine) GetAll(ctx context.Context, logger log.Logger, customerID uint64, product models.Product) ([]*models.CustomerLicense, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.GetAll",
		trace.WithAttributes(
			attribute.String("gh.customer.id", strconv.FormatUint(customerID, 10)),
			attribute.String("gh.product.name", product.String()),
		),
	)
	defer sp.End()

	pk := models.NewCustomerLicensePartitionKey(customerID, product)
	queryString := "select * from c"
	querier := cosmos.NewQuerier[*models.CustomerLicense](ce.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, nil)
}

// GetAllWithEnablement returns all customerLicenses for a customer and product with a specific enablement reason and enablementID.
func (ce *CustomerLicenseEngine) GetAllWithEnablement(ctx context.Context, logger log.Logger, customerID uint64, product models.Product, er models.EnablementReason, eID uint64) ([]*models.CustomerLicense, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.GetAllWithEnablement")
	defer sp.End()

	pk := models.NewCustomerLicensePartitionKey(customerID, product)
	queryString := "SELECT VALUE c FROM c JOIN e IN c.Enablements WHERE e.Reason = @reason AND ARRAY_CONTAINS(e.EnablementIDs, @enablementID)"
	queryOptions := &azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@enablementID", Value: eID},
			{Name: "@reason", Value: er.String()},
		},
	}
	querier := cosmos.NewQuerier[*models.CustomerLicense](ce.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, queryOptions)
}

// GetAllWithEnablementReasonsOrHighWatermark returns all customerLicenses for a customer and product with specific enablement reasons or high watermark.
func (ce *CustomerLicenseEngine) GetAllWithEnablementReasonsOrHighWatermark(ctx context.Context, logger log.Logger, customerID uint64, product models.Product) ([]*models.CustomerLicense, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.GetAllWithEnablementReasonsOrHighWatermark")
	defer sp.End()

	pk := models.NewCustomerLicensePartitionKey(customerID, product)
	orgMembershipReason := models.EnablementReasonOrgMembership.String()
	repoCollaboratorReason := models.EnablementReasonRepositoryCollaborator.String()
	licenseStatusDeactivated := models.LicenseStatusDeactivated.String()

	queryString := `
		SELECT VALUE c
		FROM c
		WHERE c.LicenseStatus = @licenseStatusDeactivated
		OR EXISTS(SELECT VALUE e FROM e IN c.Enablements WHERE e.Reason IN (@orgMembershipReason, @repoCollaboratorReason))
	`
	queryOptions := &azcosmos.QueryOptions{
		QueryParameters: []azcosmos.QueryParameter{
			{Name: "@licenseStatusDeactivated", Value: licenseStatusDeactivated},
			{Name: "@orgMembershipReason", Value: orgMembershipReason},
			{Name: "@repoCollaboratorReason", Value: repoCollaboratorReason},
		},
	}

	querier := cosmos.NewQuerier[*models.CustomerLicense](ce.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, queryOptions)
}

// Upsert creates or updates a customerLicense.
func (ce *CustomerLicenseEngine) Upsert(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, o *azcosmos.ItemOptions) error {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.Upsert")
	defer sp.End()

	// Update the TTL if the customer is expired (ExpiredAt and LicenseStatusDeactivated)
	if customerLicense.LicenseStatus == models.LicenseStatusDeactivated {
		customerLicense.CosmosProperties.TTL = models.RemainingSecondsThisMonth()
	} else {
		customerLicense.CosmosProperties.TTL = nil
	}

	marshalled, err := json.Marshal(customerLicense)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to marshal customerLicense: %w", err)
	}
	pk := azcosmos.NewPartitionKeyString(customerLicense.PartitionKey)

	itemResponse, err := ce.dbConnection.UpsertItem(
		ctx,
		pk,
		marshalled,
		o,
	)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to upsert customerLicense: %w", err)
	}
	logger.Info("CustomerLicense upserted",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)

	return nil
}

// Swap deletes an old customer license and upserts a new one in a single transaction.
func (ce *CustomerLicenseEngine) Swap(ctx context.Context, logger log.Logger, oldCustomerLicense, newCustomerLicense *models.CustomerLicense, txItemOpts *azcosmos.TransactionalBatchItemOptions) error {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.Swap")
	defer sp.End()

	// create tx
	pk := azcosmos.NewPartitionKeyString(oldCustomerLicense.PartitionKey)
	batch := ce.dbConnection.NewTransactionalBatch(pk)

	// add delete of old license to the batch
	batch.DeleteItem(oldCustomerLicense.ID, txItemOpts)

	// marshal new license and add upsert of it to the batch
	marshalled, err := json.Marshal(newCustomerLicense)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to marshal new customerLicense: %w", err)
	}
	batch.UpsertItem(marshalled, txItemOpts)

	// execute the transactional batch
	txBatchResponse, err := ce.dbConnection.ExecuteTransactionalBatch(ctx, batch, nil)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to execute transactional batch: %w", err)
	}

	// Check for success and handle any errors from the response
	if !txBatchResponse.Success {
		var responseErr error
		for i, operation := range txBatchResponse.OperationResults {
			// StatusFailedDependency (424) means an operation was not executed; used when a previous operation fails; ignore those
			if operation.StatusCode != http.StatusFailedDependency {
				var errorMsg string
				if len(operation.ResourceBody) > 0 {
					errorMsg = string(operation.ResourceBody)
				} else {
					errorMsg = "no error message available"
				}

				responseErr = fmt.Errorf("operation %d failed with status code %d. Error message: %s", i, operation.StatusCode, errorMsg)
				break
			}
		}

		if responseErr == nil {
			responseErr = fmt.Errorf("transactional batch failed with status code %d", txBatchResponse.Response.RawResponse.StatusCode)
		}

		recordError(responseErr, sp)
		return responseErr
	}

	logger.Info("CustomerLicenses swapped",
		kvp.String("db.cosmosdb.activity_id", txBatchResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", txBatchResponse.RequestCharge),
	)

	return nil
}

// GetLicenseesForProduct returns all licensees who have customerLicenses for a product.
func (ce *CustomerLicenseEngine) GetLicenseesForProduct(ctx context.Context, logger log.Logger, customerID uint64, product models.Product, statuses []models.LicenseStatus) ([]*models.Licensee, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.GetLicenseesForProduct")
	defer sp.End()
	pk := models.NewCustomerLicensePartitionKey(customerID, product)
	queryString := "select value c.Licensee from c"
	queryOptions := &azcosmos.QueryOptions{
		PageSizeHint:    -1,
		QueryParameters: []azcosmos.QueryParameter{},
	}

	if len(statuses) > 0 {
		queryString += " WHERE c.LicenseStatus IN ("
		for i, s := range statuses {
			paramName := fmt.Sprintf("@licenseStatus%d", i)
			queryString += paramName
			if i < len(statuses)-1 {
				queryString += ", "
			}
			queryOptions.QueryParameters = append(queryOptions.QueryParameters, azcosmos.QueryParameter{Name: paramName, Value: s.String()})
		}
		queryString += ")"
	}

	querier := cosmos.NewQuerier[*models.Licensee](ce.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, queryOptions)
}

// GetLicenseesForProductAndEnablementReasons returns all licensees who have customerLicenses for a product with specific enablement reasons.
// If reasons is empty, it will return all licensees for the product.
// If a licensee matches multiple reasons, it will only be returned once.
func (ce *CustomerLicenseEngine) GetLicenseesForProductAndEnablementReasons(ctx context.Context, logger log.Logger, customerID uint64, product models.Product, reasons []models.EnablementReason) ([]uint64, error) {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.GetLicenseeIds")
	defer sp.End()
	pk := models.NewCustomerLicensePartitionKey(customerID, product)
	queryString := "SELECT DISTINCT VALUE c.Licensee.ID FROM c"
	queryOptions := &azcosmos.QueryOptions{
		PageSizeHint:    -1,
		QueryParameters: []azcosmos.QueryParameter{},
	}

	if len(reasons) > 0 {
		queryString += " JOIN e IN c.Enablements WHERE e.Reason IN ("
		for i, r := range reasons {
			paramName := fmt.Sprintf("@reason%d", i)
			queryString += paramName
			if i < len(reasons)-1 {
				queryString += ", "
			}
			queryOptions.QueryParameters = append(queryOptions.QueryParameters, azcosmos.QueryParameter{Name: paramName, Value: r.String()})
		}
		queryString += ")"
	}

	querier := cosmos.NewQuerier[interface{}](ce.dbConnection)
	results, err := querier.ExecuteQuery(ctx, queryString, pk, queryOptions)
	if err != nil {
		return nil, err
	}

	licenseeIDs := make([]uint64, 0, len(results))
	for _, result := range results {
		var licenseeID uint64
		switch v := result.(type) {
		case string:
			id, err := strconv.ParseUint(v, 10, 64)
			if err != nil {
				return nil, err
			}
			licenseeID = id
		case float64:
			licenseeID = uint64(v)
		default:
			return nil, fmt.Errorf("unexpected type %T", v)
		}
		licenseeIDs = append(licenseeIDs, licenseeID)
	}

	return licenseeIDs, nil
}

// Delete deletes a CustomerLicense record by partition Key and ID.
// If the record doesn't exist it will return a 404 error.
func (ce *CustomerLicenseEngine) Delete(ctx context.Context, logger log.Logger, key models.Key, o *azcosmos.ItemOptions) error {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.Delete")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := ce.dbConnection.DeleteItem(ctx, pk, key.ID, o)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to delete customerLicense: %w", err)
	}
	logger.Info("CustomerLicense deleted",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)
	return nil
}

// Patch updates specific fields of a CustomerLicense record by partition Key and ID.
// It returns nil if the CustomerLicense record is not found.
func (ce *CustomerLicenseEngine) Patch(ctx context.Context, logger log.Logger, key models.Key, ops azcosmos.PatchOperations, o *azcosmos.ItemOptions) error {
	ctx, sp := ce.tracer.Start(ctx, "CustomerLicenseEngine.Patch")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := ce.dbConnection.PatchItem(ctx, pk, key.ID, ops, o)
	if err != nil {
		if cosmos.IsNotFoundError(err) {
			return nil
		}
		recordError(err, sp)
		return fmt.Errorf("failed to patch customerLicense: %w", err)
	}
	logger.Info("CustomerLicense patched",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)
	return nil
}
