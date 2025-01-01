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

// HandleEnterpriseManagedIdentityUnsuspended handles the EnterpriseManagedIdentityUnsuspended event.
func (eh *EventHandler) HandleEnterpriseManagedIdentityUnsuspended(ctx context.Context, logger log.Logger, message *licensingv0.EnterpriseManagedIdentityUnsuspended) (Skip, Error) {
	messageName := getSchemaName(message)
	sp := trace.SpanFromContext(ctx)

	licenseeID := strconv.FormatInt(message.GetUserId(), 10)
	customerID := uint64(message.GetBusiness().GetCustomerId())
	var suspendedAt *int64

	logger = logger.WithFields(
		kvp.Uint64("gh.hydro.msg.customer_id", customerID),
		kvp.String("gh.hydro.msg.user.id", licenseeID),
	)
	logger.Info("Begin handle enterprise managed identity unsuspended")

	ops := azcosmos.PatchOperations{}
	ops.AppendAdd("/LicenseStatus", models.LicenseStatusActive)
	ops.AppendAdd("/SuspendedAt", suspendedAt)
	ops.AppendAdd("/ExpiresAt", models.MaxExpiresAt)
	ops.AppendAdd("/ttl", -1)

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
	logger.Info("End handle enterprise managed identity unsuspended",
		kvp.Any("licensify.customer_license.key", customerLicenseKey),
		kvp.Any("licensify.licensee_license.key", licenseeLicenseKey),
	)

	return Skip{}, Error{}
}
