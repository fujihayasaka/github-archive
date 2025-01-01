package eventhandlers

import (
	"context"
	"fmt"
	"strconv"

	"github.com/Azure/azure-sdk-for-go/sdk/data/azcosmos"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-stats"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/cosmos"
	"github.com/github/licensify/internal/models"
)

// HandleMembershipUpdate handles the MembershipUpdate message.
func (eh *EventHandler) HandleMembershipUpdate(ctx context.Context, logger log.Logger, message *githubv1.MembershipUpdate) (Success, Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	customerID := uint64(message.GetCustomerId())
	userID := uint64(message.GetUser().GetId())
	licenseeID := strconv.FormatUint(userID, 10)
	msgContext := message.GetContext()
	action := message.GetAction()

	logger = logger.WithFields(
		kvp.String("gh.hydro.msg.action", action.String()),
		kvp.String("gh.hydro.msg.context", msgContext.String()),
		kvp.Uint64("gh.hydro.msg.group_id", message.GetGroupId()),
		kvp.Uint64("gh.hydro.msg.customer_id", customerID),
		kvp.Uint64("gh.hydro.msg.user.id", userID),
	)
	logger.Info("Begin handle membership update")

	if customerID == 0 {
		return Success{}, Skip{
			reason: "customer ID is 0",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}

	var modFunc func(*models.CustomerLicense, ...uint64) bool
	switch msgContext {
	case githubv1.MembershipUpdate_ORGANIZATION:
		if action == githubv1.MembershipUpdate_ADD {
			modFunc = (*models.CustomerLicense).AddOrgMemberships
		} else if action == githubv1.MembershipUpdate_REMOVE {
			modFunc = (*models.CustomerLicense).RemoveOrgMemberships
		}
	case githubv1.MembershipUpdate_REPOSITORY:
		if action == githubv1.MembershipUpdate_REMOVE {
			modFunc = (*models.CustomerLicense).RemoveRepositoryCollaborator
		}
	}

	if modFunc == nil {
		return Success{}, Skip{
			reason: "context & action aren't supported",
			tags:   stats.Tags{"reason": "context-action-unsupported"},
		}, Error{}
	}

	key := models.NewCustomerLicenseKey(
		customerID,
		models.ProductSDLC,
		models.LicenseeTypeUser,
		licenseeID,
	)

	customerLicense, err := eh.customerLicenseEngine.Get(ctx, *key)
	if err != nil {
		return Success{}, Skip{}, Error{
			Err:    fmt.Errorf("failed to lookup existing CustomerLicense: %w", err),
			origin: "read-customer-license",
			span:   sp,
		}
	}

	if customerLicense == nil {
		customerLicense = models.NewCustomerLicense(
			customerID,
			models.ProductSDLC,
			models.LicenseStatusActive,
			models.NewLicensee(models.LicenseeTypeUser, licenseeID),
			[]*models.CustomerLicenseEnablement{},
			models.MaxExpiresAt,
			nil,
		)
		customerLicense.AddETag()
	}

	customerLicense.Activate()

	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	modified := modFunc(customerLicense, message.GetGroupId())
	if !modified {
		return Success{}, Skip{
			reason: "no change to enablements",
			tags:   stats.Tags{"reason": "enablements-not-modified"},
		}, Error{}
	}

	logger = logger.WithFields(customerLicense.GetLoggerFields()...)

	var op, origin string
	if customerLicense.IsEmpty() {
		if op, origin, err = eh.handleEmptyLicense(ctx, logger, customerLicense, licenseeLicense); err != nil {
			return Success{}, Skip{}, Error{
				Err:    err,
				origin: origin,
				span:   sp,
			}
		}
	} else {
		op = "upsert"
		if origin, err := eh.upsertLicenses(ctx, logger, customerLicense, licenseeLicense); err != nil {
			return Success{}, Skip{}, Error{
				Err:    err,
				origin: origin,
				span:   sp,
			}
		}
	}

	logger.Info("End handle membership update")
	return Success{tags: stats.Tags{
		"operation": op,
		"action":    action.String(),
		"context":   msgContext.String(),
	}}, Skip{}, Error{}
}

func (eh *EventHandler) handleEmptyLicense(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, licenseeLicense *models.LicenseeLicense) (op, origin string, err error) {
	shouldDeactivateLicense, err := eh.customerEngine.HasHighWatermarkSDLCLicensing(ctx, customerLicense.CustomerID)
	if err != nil {
		return op, "get-customer-error", fmt.Errorf("failed to get customer: %w", err)
	}

	if shouldDeactivateLicense {
		op = "deactivate"
		origin, err = eh.deactivateLicenses(ctx, logger, customerLicense, licenseeLicense)
	} else {
		op = "delete"
		origin, err = eh.deleteLicenses(ctx, logger, customerLicense, licenseeLicense)
	}
	return op, origin, err
}

func (eh *EventHandler) deleteLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, licenseeLicense *models.LicenseeLicense) (origin string, err error) {
	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	logger.Debug("deleting CustomerLicense")
	if err := eh.customerLicenseEngine.Delete(ctx, logger, *customerLicense.Key, opts); err != nil {
		return "delete-customer-license", fmt.Errorf("failed to delete CustomerLicense %w", err)
	}

	logger.Debug("deleting LicenseeLicense")
	if err := eh.licenseeLicenseEngine.Delete(ctx, logger, *licenseeLicense.Key, nil); err != nil && !cosmos.IsNotFoundError(err) {
		return "delete-licensee-license", fmt.Errorf("failed to delete LicenseeLicense %w", err)
	}

	return "", nil
}

func (eh *EventHandler) deactivateLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, licenseeLicense *models.LicenseeLicense) (origin string, err error) {
	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	customerLicense.Deactivate()

	logger.Debug("upserting deactivated CustomerLicense")
	if err := eh.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		return "upsert-customer-license", fmt.Errorf("failed to upsert CustomerLicense %w", err)
	}

	licenseeLicense.LicenseStatus = models.LicenseStatusDeactivated
	licenseeLicense.ExpiresAt = models.EndOfMonth()

	logger.Debug("upserting deactivated LicenseeLicense")
	if err := eh.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		return "upsert-licensee-license", fmt.Errorf("failed to upsert LicenseeLicense %w", err)
	}

	return "", nil
}

func (eh *EventHandler) upsertLicenses(ctx context.Context, logger log.Logger, customerLicense *models.CustomerLicense, licenseeLicense *models.LicenseeLicense) (origin string, err error) {
	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}

	logger.Debug("upserting CustomerLicense")
	if err := eh.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		return "upsert-customer-license", fmt.Errorf("failed to upsert CustomerLicense %w", err)
	}

	logger.Debug("upserting LicenseeLicense")
	if err := eh.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		return "upsert-licensee-license", fmt.Errorf("failed to upsert LicenseeLicense %w", err)
	}

	return "", nil
}
