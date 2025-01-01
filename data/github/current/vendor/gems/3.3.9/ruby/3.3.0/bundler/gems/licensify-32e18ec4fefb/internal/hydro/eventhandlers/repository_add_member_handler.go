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
	"github.com/github/licensify/internal/models"
)

// HandleRepositoryAddMember handles the RepositoryAddMember message.
func (eh *EventHandler) HandleRepositoryAddMember(ctx context.Context, logger log.Logger, message *githubv1.RepositoryAddMember) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	customerID := uint64(message.GetRepositoryOwnerCustomerId())
	repositoryID := uint64(message.GetRepository().GetId())
	userID := uint64(message.GetMember().GetId())
	licenseeID := strconv.FormatUint(userID, 10)

	logger = logger.WithFields(
		kvp.Uint64("gh.hydro.msg.customer_id", customerID),
		kvp.Uint64("gh.hydro.msg.user.id", userID),
		kvp.Uint64("gh.hydro.msg.repository.id", repositoryID),
	)
	logger.Info("Begin handle repository add member")

	repository := &models.Repository{
		ID:                  repositoryID,
		CustomerID:          customerID,
		Visibility:          models.RepositoryVisibility(message.GetRepository().GetVisibility().Number()),
		IsAdvisoryWorkspace: message.GetIsRepositoryAdvisoryWorkspace(),
		IsFork:              message.GetRepository().GetIsFork(),
		ParentID:            message.GetRepository().GetParentId(),
	}

	if repository.MissingRequiredIDs() {
		return Skip{
			reason: "unable to process repository",
			tags:   stats.Tags{"reason": "unable-to-process"},
		}, Error{}
	}
	if repository.FeaturesDoNotConsumeLicenses() {
		return Skip{
			reason: "repository features do not consume licenses",
			tags:   stats.Tags{"reason": "repo-features-do-not-consume-licenses"},
		}, Error{}
	}
	if !repository.VisibilityConsumesLicenses() {
		return Skip{
			reason: "repository visibility does not consume licenses",
			tags:   stats.Tags{"reason": "repo-visibility-does-not-consume-licenses"},
		}, Error{}
	}
	if userID == 0 {
		return Skip{
			reason: "licensee ID is 0",
			tags:   stats.Tags{"reason": "missing-licensee-id"},
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
		return Skip{}, Error{
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
	licenseeLicense := models.NewLicenseeLicenseForCustomerLicense(customerLicense)

	modified := customerLicense.AddRepositoryCollaborators(repositoryID)
	if !modified {
		return Skip{
			reason: "no change to enablement",
			tags:   stats.Tags{"reason": "enablements-not-modified"},
		}, Error{}
	}

	logger = logger.WithFields(customerLicense.GetLoggerFields()...)

	var opts *azcosmos.ItemOptions
	if customerLicense.ETag != nil {
		opts = &azcosmos.ItemOptions{IfMatchEtag: customerLicense.ETag}
	}
	logger.Debug("upserting CustomerLicense")
	if err := eh.customerLicenseEngine.Upsert(ctx, logger, customerLicense, opts); err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to upsert CustomerLicense: %w", err),
			origin: "upsert-customer-license",
			span:   sp,
		}
	}
	logger.Debug("upserting LicenseeLicense")
	if err := eh.licenseeLicenseEngine.Upsert(ctx, logger, licenseeLicense, nil); err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to upsert LicenseeLicense: %w", err),
			origin: "upsert-licensee-license",
			span:   sp,
		}
	}

	logger.Info("End handle repository add member")
	return Skip{}, Error{}
}
