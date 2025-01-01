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

// LicenseeLicenseEngine is the engine for licenseeLicenses.
type LicenseeLicenseEngine struct {
	statter      stats.Client
	tracer       trace.Tracer
	dbConnection cosmos.ReadWriter
}

// NewLicenseeLicenseEngine creates a new LicenseeLicenseEngine.
func NewLicenseeLicenseEngine(statter stats.Client, tracer trace.Tracer, dbConnection cosmos.ReadWriter) *LicenseeLicenseEngine {
	return &LicenseeLicenseEngine{
		statter:      statter,
		tracer:       tracer,
		dbConnection: dbConnection,
	}
}

// Get looks up a LicenseeLicense by partition Key and ID. It returns nil if the LicenseeLicense is not found.
func (le *LicenseeLicenseEngine) Get(ctx context.Context, logger log.Logger, key models.Key) (*models.LicenseeLicense, error) {
	ctx, sp := le.tracer.Start(ctx, "LicenseeLicenseEngine.Get")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := le.dbConnection.ReadItem(ctx, pk, key.ID, nil)
	if err != nil {
		if cosmos.IsNotFoundError(err) {
			return nil, nil
		}
		recordError(err, sp)
		return nil, fmt.Errorf("failed to get licenseeLicense: %w", err)
	}
	var ll models.LicenseeLicense
	if err := json.Unmarshal(itemResponse.Value, &ll); err != nil {
		recordError(err, sp)
		return nil, fmt.Errorf("failed to unmarshal licenseeLicense: %w", err)
	}
	return &ll, nil
}

// GetAll returns all licensee licenses by user ID.
func (le *LicenseeLicenseEngine) GetAll(ctx context.Context, logger log.Logger, userID uint32) ([]*models.LicenseeLicense, error) {
	ctx, sp := le.tracer.Start(ctx, "LicenseeLicenseEngine.GetAll")
	defer sp.End()

	licenseeID := strconv.FormatUint(uint64(userID), 10)
	pk := models.NewLicenseeLicensePartitionKey(licenseeID, models.LicenseeTypeUser)
	queryString := "select * from c"

	querier := cosmos.NewQuerier[*models.LicenseeLicense](le.dbConnection)
	return querier.ExecuteQuery(ctx, queryString, pk, nil)
}

// Upsert creates or updates a licenseeLicense.
func (le *LicenseeLicenseEngine) Upsert(ctx context.Context, logger log.Logger, licenseeLicense *models.LicenseeLicense, o *azcosmos.ItemOptions) error {
	ctx, sp := le.tracer.Start(ctx, "LicenseeLicenseEngine.Upsert")
	defer sp.End()

	// Update the TTL if the customer is expired (ExpiredAt and LicenseStatusDeactivated)
	if licenseeLicense.LicenseStatus == models.LicenseStatusDeactivated {
		licenseeLicense.CosmosProperties.TTL = models.RemainingSecondsThisMonth()
	} else {
		licenseeLicense.CosmosProperties.TTL = nil
	}

	marshalled, err := json.Marshal(licenseeLicense)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to marshal licenseeLicense: %w", err)
	}
	pk := azcosmos.NewPartitionKeyString(licenseeLicense.PartitionKey)

	itemResponse, err := le.dbConnection.UpsertItem(
		ctx,
		pk,
		marshalled,
		o,
	)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to upsert licenseeLicense: %w", err)
	}
	logger.Info("LicenseeLicense upserted",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)

	return nil
}

// Delete deletes a LicenseeLicense record by partition Key and ID.
// If the record doesn't exist it will return a 404 error.
func (le *LicenseeLicenseEngine) Delete(ctx context.Context, logger log.Logger, key models.Key, o *azcosmos.ItemOptions) error {
	ctx, sp := le.tracer.Start(ctx, "LicenseeLicenseEngine.Delete")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := le.dbConnection.DeleteItem(ctx, pk, key.ID, o)
	if err != nil {
		recordError(err, sp)
		return fmt.Errorf("failed to delete licenseeLicense: %w", err)
	}
	logger.Info("LicenseeLicense deleted",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)
	return nil
}

// Patch updates specific fields of a LicenseeLicense record by partition Key and ID.
// It returns nil if the LicenseeLicense record is not found.
func (le *LicenseeLicenseEngine) Patch(ctx context.Context, logger log.Logger, key models.Key, ops azcosmos.PatchOperations, o *azcosmos.ItemOptions) error {
	ctx, sp := le.tracer.Start(ctx, "LicenseeLicenseEngine.Patch")
	defer sp.End()
	pk := azcosmos.NewPartitionKeyString(key.PartitionKey)
	itemResponse, err := le.dbConnection.PatchItem(ctx, pk, key.ID, ops, o)
	if err != nil {
		if cosmos.IsNotFoundError(err) {
			return nil
		}
		recordError(err, sp)
		return fmt.Errorf("failed to patch licenseeLicense: %w", err)
	}
	logger.Info("LicenseeLicense patched",
		kvp.String("db.cosmosdb.activity_id", itemResponse.ActivityID),
		kvp.Float32("db.cosmosdb.request_charge", itemResponse.RequestCharge),
	)
	return nil
}
