package handlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/aqueduct-client-go/v2/pkg/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/trace"
)

// BackfillLicenseStatusHandler is an aqueduct message handler for backfilling license status.
type BackfillLicenseStatusHandler struct {
	dbReadWriter          cosmos.ReadWriter
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
	statter               stats.Client
	tracer                trace.Tracer
}

// NewBackfillLicenseStatusHandler creates a new aqueduct message handler for backfilling license status.
func NewBackfillLicenseStatusHandler(statter stats.Client, tracer trace.Tracer, dbReadWriter cosmos.ReadWriter, customerLicenseEngine *engines.CustomerLicenseEngine, licenseeLicenseEngine *engines.LicenseeLicenseEngine) *BackfillLicenseStatusHandler {
	return &BackfillLicenseStatusHandler{
		statter:               statter,
		tracer:                tracer,
		dbReadWriter:          dbReadWriter,
		customerLicenseEngine: customerLicenseEngine,
		licenseeLicenseEngine: licenseeLicenseEngine,
	}
}

// ProcessMessage takes a customerID, looks up all CustomerLicenses and LicenseeLicenses for the customer,
// and sets the LicenseStatus to active if the LicenseStatus is not already set.
func (h *BackfillLicenseStatusHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, sp := h.tracer.Start(ctx, "BackfillLicenseStatusHandler.ProcessMessage")
	defer sp.End()

	var msg *models.BackfillLicenseStatusJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return err
	}

	logger = logger.WithFields(msg.GetLoggerFields()...)
	logger.Info("Processing backfill license status message", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))

	customerID := msg.CustomerID

	licenseeIDs, err := h.customerLicenseEngine.GetLicenseesForProductAndEnablementReasons(ctx, logger, customerID, models.ProductSDLC, nil)
	if err != nil {
		h.trackError(err, "get-licensees-error", sp, logger)
		return err
	}
	logger.Info("found licensees", kvp.Int("gh.licensify.licensees.count", len(licenseeIDs)))

	var count int
	failed := make([]uint64, 0)
	for _, licenseeID := range licenseeIDs {
		if err := h.addLicenseStatus(ctx, logger, customerID, licenseeID); err != nil {
			h.trackError(err, "add-license-status-error", sp, logger)
			failed = append(failed, licenseeID)
			continue
		}
		count++
	}

	logger.Info("backfilled license status",
		kvp.Int("licensees.updated_count", count),
		kvp.Int("licensee.failed_count", len(failed)),
		kvp.Any("licensee.failed", failed),
	)
	h.statter.Counter("backfill_license_status.licensees_updated", nil, int64(count))
	return nil
}

func (h *BackfillLicenseStatusHandler) addLicenseStatus(ctx context.Context, logger log.Logger, customerID, licenseeID uint64) error {
	ops := azcosmos.PatchOperations{}
	ops.AppendAdd("/LicenseStatus", models.LicenseStatusActive)
	ops.SetCondition("from c where not is_defined(c.LicenseStatus) or c.LicenseStatus = ''")

	// Patch the customer license
	customerLicenseKey := models.NewCustomerLicenseKey(
		customerID,
		models.ProductSDLC,
		models.LicenseeTypeUser,
		strconv.FormatUint(licenseeID, 10),
	)
	_, err := h.dbReadWriter.PatchItem(
		ctx,
		azcosmos.NewPartitionKeyString(customerLicenseKey.PartitionKey),
		customerLicenseKey.ID,
		ops,
		nil,
	)
	// If the license already has a LicenseStatus, the request will fail with a PreconditionFailed error
	// in which case we can ignore it
	if err != nil && !cosmos.IsPreconditionFailedError(err) {
		logger.WithError(err).Error("failed to patch customer license")
		return err
	}

	// Patch the licensee license
	licenseeLicenseKey := models.NewLicenseeLicenseKey(
		strconv.FormatUint(licenseeID, 10),
		models.LicenseeTypeUser,
		models.ProductSDLC,
		customerID,
	)
	_, err = h.dbReadWriter.PatchItem(
		ctx,
		azcosmos.NewPartitionKeyString(licenseeLicenseKey.PartitionKey),
		licenseeLicenseKey.ID,
		ops,
		nil,
	)
	// If the license already has a LicenseStatus, the request will fail with a PreconditionFailed error
	// in which case we can ignore it
	if err != nil && !cosmos.IsPreconditionFailedError(err) {
		logger.WithError(err).Error("failed to patch licensee license")
		return err
	}
	logger.Info("added license status",
		kvp.Any("licensify.customer_license.key", customerLicenseKey),
		kvp.Any("licensify.licensee_license.key", licenseeLicenseKey),
	)
	return nil
}

func (h *BackfillLicenseStatusHandler) trackError(err error, origin string, sp trace.Span, logger log.Logger) {
	h.statter.Counter("backfill_license_status_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error backfilling license status")
	sp.RecordError(err)
	sp.SetStatus(codes.Error, origin)
}
