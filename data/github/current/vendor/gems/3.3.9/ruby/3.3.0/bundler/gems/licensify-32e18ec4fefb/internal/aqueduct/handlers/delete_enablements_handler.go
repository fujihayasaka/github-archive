package handlers

import (
	"context"
	"encoding/json"
	"fmt"

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

// DeleteEnablementsHandler is an aqueduct message handler for deleting enablements.
type DeleteEnablementsHandler struct {
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
	customerEngine        *engines.CustomerEngine
	statter               stats.Client
	tracer                trace.Tracer
}

// NewDeleteEnablementsHandler creates a new aqueduct message handler for deleting enablements.
func NewDeleteEnablementsHandler(statter stats.Client, tracer trace.Tracer, customerLicenseEngine *engines.CustomerLicenseEngine, licenseeLicenseEngine *engines.LicenseeLicenseEngine, customerEngine *engines.CustomerEngine) *DeleteEnablementsHandler {
	return &DeleteEnablementsHandler{
		statter:               statter,
		tracer:                tracer,
		customerLicenseEngine: customerLicenseEngine,
		licenseeLicenseEngine: licenseeLicenseEngine,
		customerEngine:        customerEngine,
	}
}

// ProcessMessage takes an aqueduct message for deleting enablements.
// It expects a message with the following structure: { "customerID": 123, "EnablementReason": models.EnablementReasonOrgMembership, "EnablementID": 456 }
// The job removes the EnablementID from all customer licenses with that enablement and upserts/deletes the license.
func (h *DeleteEnablementsHandler) ProcessMessage(ctx context.Context, logger log.Logger, rr aqueduct.ReceiveResult) error {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.ProcessMessage")
	defer sp.End()

	var msg *models.DeleteEnablementsJob
	if err := json.Unmarshal(rr.Payload, &msg); err != nil {
		logger.WithError(err).Error("Failed to unmarshal message")
		return err
	}

	logger = logger.WithFields(
		kvp.Uint64("gh.customer.id", msg.CustomerID),
		kvp.String("gh.enablement_reason", msg.EnablementReason.String()),
		kvp.Uint64("gh.enablement_id", msg.EnablementID),
	)
	logger.Info("Processing delete enablements message", kvp.String("gh.aqueduct.job.payload", fmt.Sprintf("%+v", *msg)))

	if msg.EnablementID == 0 {
		logger.Info("EnablementID is 0, skipping")
		return nil
	}
	if msg.EnablementReason == models.EnablementReasonUnspecified {
		logger.Info("EnablementReason is unknown, skipping")
		return nil
	}
	if msg.CustomerID == 0 {
		logger.Info("CustomerID is 0, skipping")
		return nil
	}

	licenses, err := h.customerLicenseEngine.GetAllWithEnablement(
		ctx,
		logger,
		msg.CustomerID,
		models.ProductSDLC,
		msg.EnablementReason,
		msg.EnablementID,
	)
	if err != nil {
		h.trackError(err, "get-customer-licenses-error", sp, logger)
		return fmt.Errorf("failed to get customer licenses: %w", err)
	}

	logger.Info("Found customer licenses", kvp.Int("count", len(licenses)))

	shouldDeactivateLicenses, err := h.customerEngine.HasHighWatermarkSDLCLicensing(ctx, msg.CustomerID)
	if err != nil {
		err := fmt.Errorf("failed to get customer: %w", err)
		h.trackError(err, "get-customer-error", sp, logger)
		return err
	}

	customerLicenseOps := make(map[operation][]string)
	licenseeLicenseOps := make(map[operation][]string)

	for _, cl := range licenses {
		customerLicenseOp, licenseeLicenseOp, err := h.removeEnablementReasonFromLicenseWithRetries(ctx, logger, cl, shouldDeactivateLicenses, msg.EnablementReason, msg.EnablementID)
		if err != nil {
			return err
		}

		h.trackOperation(customerLicenseOp, "customer_license", msg.EnablementReason)
		h.trackOperation(licenseeLicenseOp, "licensee_license", msg.EnablementReason)
		customerLicenseOps[customerLicenseOp] = append(customerLicenseOps[customerLicenseOp], cl.Licensee.ID)
		licenseeLicenseOps[licenseeLicenseOp] = append(licenseeLicenseOps[licenseeLicenseOp], cl.Licensee.ID)
	}

	logger.Info("Delete enablements message processed successfully",
		kvp.Int("customer_license.upserted_count", len(customerLicenseOps[operationUpserted])),
		kvp.Int("customer_license.deleted_count", len(customerLicenseOps[operationDeleted])),
		kvp.Int("customer_license.not_modified_count", len(customerLicenseOps[operationNotModified])),
		kvp.Any("customer_license.upserted_ids", customerLicenseOps[operationUpserted]),
		kvp.Any("customer_license.deleted_ids", customerLicenseOps[operationDeleted]),
		kvp.Int("licensee_license.upserted_count", len(licenseeLicenseOps[operationUpserted])),
		kvp.Int("licensee_license.deleted_count", len(licenseeLicenseOps[operationDeleted])),
		kvp.Any("licensee_license.upserted_ids", licenseeLicenseOps[operationUpserted]),
		kvp.Any("licensee_license.deleted_ids", licenseeLicenseOps[operationDeleted]),
	)

	return nil
}

func (h *DeleteEnablementsHandler) removeEnablementReasonFromLicenseWithRetries(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, shouldDeactivateLicenses bool, enablementReason models.EnablementReason, enablementID uint64) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.removeEnablementReasonFromLicenseWithRetries")
	defer sp.End()

	const retries = 10

	for i := range retries {
		logger := logger.WithFields(kvp.Int("retry", i))
		latestCustomerLicense := customerLicense
		if i > 0 {
			// If we're retrying, get the latest version of the CustomerLicense
			latestCustomerLicense, err = h.customerLicenseEngine.Get(ctx, *customerLicense.Key)
			if err != nil {
				h.trackError(err, "get-customer-license-error", sp, logger)
				return "", "", fmt.Errorf("failed to get customer license: %w", err)
			}
		}
		customerLicenseOp, licenseeLicenseOp, err = h.removeEnablementReasonFromLicense(ctx, logger, shouldDeactivateLicenses, latestCustomerLicense, enablementReason, enablementID)
		if err != nil {
			if cosmos.IsPreconditionFailedError(err) {
				continue
			}
			return "", "", fmt.Errorf("failed to remove enablement from license: %w", err)
		}
		return customerLicenseOp, licenseeLicenseOp, nil
	}

	err = fmt.Errorf("failed to remove enablement from license after %d retries: %w", retries, err)
	h.trackError(err, "remove-enablement-retries-exhausted", sp, logger)
	return "", "", err
}

func (h *DeleteEnablementsHandler) removeEnablementReasonFromLicense(ctx context.Context, logger log.Logger, shouldDeactivateLicenses bool, customerLicense *models.CustomerLicense, enablementReason models.EnablementReason, enablementID uint64) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.removeEnablementReasonFromLicense")
	defer sp.End()

	var modFunc func(*models.CustomerLicense, ...uint64) bool
	switch enablementReason {
	case models.EnablementReasonOrgMembership:
		modFunc = (*models.CustomerLicense).RemoveOrgMemberships
	case models.EnablementReasonRepositoryCollaborator:
		modFunc = (*models.CustomerLicense).RemoveRepositoryCollaborator
	}

	if modFunc == nil {
		logger.Info("enablement reason not supported, skipping")
		return "", "", nil
	}

	modified := modFunc(customerLicense, enablementID)
	if !modified {
		return "", "", nil
	}

	// If the customer license is empty then there are no enablements
	// We need to set metered customers to be inactive
	// Non metered customers will be deleted
	if customerLicense.IsEmpty() {
		if shouldDeactivateLicenses {
			return h.deactivateLicenses(ctx, logger, customerLicense)
		}
		return h.deleteLicenses(ctx, logger, customerLicense)
	}

	return h.upsertLicenses(ctx, logger, customerLicense)
}

func (h *DeleteEnablementsHandler) trackError(err error, origin string, span trace.Span, logger log.Logger) {
	h.statter.Counter("delete_enablements_error",
		stats.Tags{"origin": origin},
		int64(1),
	)
	logger.WithError(err).Error("error deleting enablements")
	span.RecordError(err)
	span.SetStatus(codes.Error, origin)
}

func (h *DeleteEnablementsHandler) trackOperation(operation operation, documentType string, enablementReason models.EnablementReason) {
	h.statter.Counter(
		"delete_enablements.license_operations",
		stats.Tags{
			"operation":         string(operation),
			"document":          documentType,
			"enablement_reason": enablementReason.String(),
		},
		int64(1),
	)
}

// deleteLicenses deletes the customer and licensee licenses
func (h *DeleteEnablementsHandler) deleteLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.deleteLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	if err := h.customerLicenseEngine.Delete(ctx, logger, *customerLicense.Key, opts); err != nil && !cosmos.IsNotFoundError(err) {
		origin := "delete-customer-license-error"
		if cosmos.IsPreconditionFailedError(err) {
			origin = "delete-customer-license-precondition-failed"
		}
		h.trackError(err, origin, sp, logger)
		return "", "", fmt.Errorf("failed to delete customer license: %w", err)
	}
	customerLicenseOp = operationDeleted

	licenseeLicenseKey := customerLicense.GetLicenseeLicenseKey()
	if err := h.licenseeLicenseEngine.Delete(ctx, logger, *licenseeLicenseKey, nil); err != nil && !cosmos.IsNotFoundError(err) {
		h.trackError(err, "delete-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to delete licensee license: %w", err)
	}
	licenseeLicenseOp = operationDeleted
	return customerLicenseOp, licenseeLicenseOp, nil
}

// deactivateLicenses sets customer licenses to be inactive and expire at the end of the month
func (h *DeleteEnablementsHandler) deactivateLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.deactivateLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	customerLicense.Deactivate()

	if err := h.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		origin := "upsert-customer-license-error"
		if cosmos.IsPreconditionFailedError(err) {
			origin = "deactivate-customer-license-precondition-failed"
		}
		h.trackError(err, origin, sp, logger)
		return "", "", fmt.Errorf("failed to upsert customer license: %w", err)
	}
	customerLicenseOp = operationDeactivated

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	if err = h.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		h.trackError(err, "upsert-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to upsert licensee license: %w", err)
	}
	licenseeLicenseOp = operationDeactivated

	return customerLicenseOp, licenseeLicenseOp, nil
}

// upsertLicenses creates or updates the customer and licensee licenses
func (h *DeleteEnablementsHandler) upsertLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense) (customerLicenseOp, licenseeLicenseOp operation, err error) {
	ctx, sp := h.tracer.Start(ctx, "DeleteEnablementsHandler.upsertLicenses")
	defer sp.End()

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	customerLicense.Activate()

	if err := h.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		origin := "upsert-customer-license-error"
		if cosmos.IsPreconditionFailedError(err) {
			origin = "upsert-customer-license-precondition-failed"
		}
		h.trackError(err, origin, sp, logger)
		return "", "", fmt.Errorf("failed to upsert customer license: %w", err)
	}
	customerLicenseOp = operationUpserted

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)
	if err = h.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		h.trackError(err, "upsert-licensee-license-error", sp, logger)
		return "", "", fmt.Errorf("failed to upsert licensee license: %w", err)
	}
	licenseeLicenseOp = operationUpserted

	return customerLicenseOp, licenseeLicenseOp, nil
}
