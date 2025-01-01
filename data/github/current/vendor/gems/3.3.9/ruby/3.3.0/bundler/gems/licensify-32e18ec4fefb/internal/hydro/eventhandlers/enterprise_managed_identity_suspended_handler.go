package eventhandlers

import (
	"context"
	"fmt"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	licensingv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/licensing/v0"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleEnterpriseManagedIdentitySuspended handles the EnterpriseManagedIdentitySuspended message.
func (eh *EventHandler) HandleEnterpriseManagedIdentitySuspended(ctx context.Context, logger log.Logger, message *licensingv0.EnterpriseManagedIdentitySuspended) (Skip, Error) {
	messageName := getSchemaName(message)
	sp := trace.SpanFromContext(ctx)

	licenseeID := strconv.FormatInt(message.GetUserId(), 10)
	customerID := uint64(message.GetBusiness().GetCustomerId())
	suspendedAt := getSuspendedAtTimestamp(message)

	logger = logger.WithFields(
		kvp.Uint64("gh.hydro.msg.customer_id", customerID),
		kvp.String("gh.hydro.msg.user.id", licenseeID),
	)
	logger.Info("Begin handle enterprise managed identity suspended")

	ops := azcosmos.PatchOperations{}
	ops.AppendAdd("/LicenseStatus", models.LicenseStatusSuspended)
	ops.AppendAdd("/SuspendedAt", suspendedAt)

	// Patch the customer license
	customerLicenseKey := models.NewCustomerLicenseKey(
		customerID,
		models.ProductSDLC,
		models.LicenseeTypeUser,
		licenseeID,
	)
	err := eh.customerLicenseEngine.Patch(
		ctx,
		logger,
		*customerLicenseKey,
		ops,
		nil,
	)

	if err != nil {
		herr := Error{
			Err:    fmt.Errorf("failed to patch customer license: %w", err),
			origin: "customer-license-patch",
			span:   sp,
		}
		eh.trackError(logger, herr, messageName)
		return Skip{}, herr
	}

	// Patch the licensee license
	licenseeLicenseKey := models.NewLicenseeLicenseKey(
		licenseeID,
		models.LicenseeTypeUser,
		models.ProductSDLC,
		customerID,
	)
	err = eh.licenseeLicenseEngine.Patch(
		ctx,
		logger,
		*licenseeLicenseKey,
		ops,
		nil,
	)

	if err != nil {
		herr := Error{
			Err:    fmt.Errorf("failed to patch licensee license: %w", err),
			origin: "licensee-license-patch",
			span:   sp,
		}
		eh.trackError(logger, herr, messageName)
		return Skip{}, herr
	}
	logger.Info("End handle enterprise managed identity suspended",
		kvp.Any("licensify.customer_license.key", customerLicenseKey),
		kvp.Any("licensify.licensee_license.key", licenseeLicenseKey),
	)

	return Skip{}, Error{}
}

// getSuspendedAtTimestamp returns the suspended at timestamp if it exists
func getSuspendedAtTimestamp(message *licensingv0.EnterpriseManagedIdentitySuspended) *int64 {
	if message.GetSuspendedAt() != nil {
		timestamp := message.GetSuspendedAt().AsTime().Unix()
		return &timestamp
	}
	return nil
}
