package eventhandlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	entities "github.com/github/hydro-schemas-go/hydro/schemas/github/v1/entities"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/engines"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// UserDestroyHandler is the handler for the UserDestroy message. It handles user and org deletions.
type userDestroyHandler struct {
	ctx                   context.Context
	message               *githubv1.UserDestroy
	statter               stats.Client
	logger                log.Logger
	span                  trace.Span
	jobby                 *jobs.Jobby
	trackError            func(herr Error)
	customerEngine        *engines.CustomerEngine
	customerLicenseEngine *engines.CustomerLicenseEngine
	licenseeLicenseEngine *engines.LicenseeLicenseEngine
}

// HandleUserDestroy handles the UserDestroy message. For orgs, it queues a job to delete org memberships.
func (eh *EventHandler) HandleUserDestroy(ctx context.Context, logger log.Logger, message *githubv1.UserDestroy) (Skip, Error) {
	messageName := getSchemaName(message)

	span := trace.SpanFromContext(ctx)

	userType := message.GetUser().GetType()
	statter := eh.statter.WithTags(stats.Tags{"user_type": userType.String()})

	userDestroyHander := &userDestroyHandler{
		ctx:     ctx,
		message: message,
		statter: statter,
		logger:  logger,
		span:    span,
		jobby:   eh.jobby,
		trackError: func(herr Error) {
			eh.trackError(logger, herr, messageName)
		},
		customerEngine:        eh.customerEngine,
		customerLicenseEngine: eh.customerLicenseEngine,
		licenseeLicenseEngine: eh.licenseeLicenseEngine,
	}

	var skip Skip
	var herr Error
	switch userType {
	case entities.User_ORGANIZATION:
		skip, herr = userDestroyHander.handleOrganizationDestroy()
		if !herr.IsEmpty() {
			herr.Err = fmt.Errorf("failed to handle organization destroy: %w", herr.Err)
		}
	case entities.User_USER:
		skip, herr = userDestroyHander.handleUserDestroy()
		if !herr.IsEmpty() {
			herr.Err = fmt.Errorf("failed to handle user destroy: %w", herr.Err)
		}
	default:
		skip = Skip{
			reason: "user type is not supported",
			tags:   stats.Tags{"reason": "unsupported-user-type"},
		}
	}

	return skip, herr
}

func (udh *userDestroyHandler) handleOrganizationDestroy() (Skip, Error) {
	message := udh.message
	customerID := message.GetOrganizationCustomerId()
	organizationID := message.GetUser().GetId()

	udh.logger = udh.logger.WithFields(
		kvp.Int64("gh.customer.id", customerID),
		kvp.Uint32("gh.organization.id", organizationID),
	)
	udh.logger.Info("Begin handle organization destroy")

	if customerID == 0 {
		return Skip{
			reason: "customer ID is 0",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}

	if organizationID == 0 {
		return Skip{
			reason: "organization ID is 0",
			tags:   stats.Tags{"reason": "missing-organization-id"},
		}, Error{}
	}

	job := &models.DeleteEnablementsJob{
		CustomerID:       uint64(customerID),
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     uint64(organizationID),
	}

	payload, err := json.Marshal(job)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to marshal job: %w", err),
			origin: "marshal-job",
			span:   udh.span,
		}
	}

	jobID, err := udh.jobby.Enqueue(udh.ctx, jobs.JobNameDeleteEnablements, queues.QueueDeleteEnablements, payload)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("send to send job to aqueduct: %w", err),
			origin: "send-job",
			span:   udh.span,
		}
	}

	udh.logger.Info("delete-enablements job queued",
		kvp.String("gh.aqueduct.job.id", jobID),
		kvp.String("gh.licensify.job", fmt.Sprintf("%+v", job)),
	)

	udh.logger.Info("End handle organization destroy")
	return Skip{}, Error{}
}

func (udh *userDestroyHandler) handleUserDestroy() (Skip, Error) {
	userID := udh.message.GetUser().GetId()

	udh.logger = udh.logger.WithFields(
		kvp.Uint32("gh.user.id", userID),
	)
	udh.logger.Info("Begin handle user destroy")

	if userID == 0 {
		return Skip{
			reason: "user ID is 0",
			tags:   stats.Tags{"reason": "missing-user-id"},
		}, Error{}
	}

	licenseeLicenses, err := udh.licenseeLicenseEngine.GetAll(udh.ctx, udh.logger, userID)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to get all licensee licenses: %w", err),
			origin: "get-all-licensee-licenses",
			span:   udh.span,
		}
	}

	var deletedCustomerLicenses int
	var deletedLicenseeLicenses int
	var expiredCustomerLicenses int
	var expiredLicenseeLicenses int

	for _, licenseeLicense := range licenseeLicenses {
		customerID := licenseeLicense.CustomerID
		shouldDeactivateLicenses, err := udh.customerEngine.HasHighWatermarkSDLCLicensing(udh.ctx, customerID)
		if err != nil {
			return Skip{}, Error{
				Err:    fmt.Errorf("failed to get customer: %w", err),
				origin: "get-customer-error",
				span:   udh.span,
			}
		}
		if shouldDeactivateLicenses {
			udh.deactivateLicenses(licenseeLicense, &expiredCustomerLicenses, &expiredLicenseeLicenses)
		} else {
			udh.deleteLicenses(licenseeLicense, &deletedCustomerLicenses, &deletedLicenseeLicenses)
		}
	}

	udh.statter.Counter("user_destroy.customer_licenses", nil, int64(deletedCustomerLicenses))
	udh.statter.Counter("user_destroy.licensee_licenses", nil, int64(deletedLicenseeLicenses))
	udh.statter.Counter("user_expire.customer_licenses", nil, int64(expiredCustomerLicenses))
	udh.statter.Counter("user_expire.licensee_licenses", nil, int64(expiredLicenseeLicenses))

	udh.logger.Info("End handle user destroy")
	return Skip{}, Error{}
}

func (udh *userDestroyHandler) deleteLicenses(licenseeLicense *models.LicenseeLicense, deletedCustomerLicenses, deletedLicenseeLicenses *int) {
	customerLicenseKey := licenseeLicense.BuildCustomerLicenseKey()

	if err := udh.customerLicenseEngine.Delete(udh.ctx, udh.logger, *customerLicenseKey, nil); err != nil {
		udh.trackError(Error{
			Err:    fmt.Errorf("failed to delete customer license: %w", err),
			origin: "customer-license-delete",
			span:   udh.span,
		})
	} else {
		*deletedCustomerLicenses++
	}

	if err := udh.licenseeLicenseEngine.Delete(udh.ctx, udh.logger, *licenseeLicense.Key, nil); err != nil {
		udh.trackError(Error{
			Err:    fmt.Errorf("failed to delete licensee license: %w", err),
			origin: "licensee-license-delete",
			span:   udh.span,
		})
	} else {
		*deletedLicenseeLicenses++
	}
}

func (udh *userDestroyHandler) deactivateLicenses(licenseeLicense *models.LicenseeLicense, expiredCustomerLicenses, expiredLicenseeLicenses *int) {
	customerLicense := licenseeLicense.BuildCustomerLicense()

	customerLicense.LicenseStatus = models.LicenseStatusDeactivated
	customerLicense.ExpiresAt = models.EndOfMonth()

	if err := udh.customerLicenseEngine.Upsert(udh.ctx, udh.logger.WithFields(customerLicense.GetLoggerFields()...), customerLicense, nil); err != nil {
		udh.trackError(Error{
			Err:    fmt.Errorf("failed to expire customer license: %w", err),
			origin: "customer-license-expire",
			span:   udh.span,
		})
	} else {
		*expiredCustomerLicenses++
	}

	licenseeLicense.LicenseStatus = models.LicenseStatusDeactivated
	licenseeLicense.ExpiresAt = models.EndOfMonth()

	if err := udh.licenseeLicenseEngine.Upsert(udh.ctx, udh.logger.WithFields(licenseeLicense.GetLoggerFields()...), licenseeLicense, nil); err != nil {
		udh.trackError(Error{
			Err:    fmt.Errorf("failed to expire licensee license: %w", err),
			origin: "licensee-license-expire",
			span:   udh.span,
		})
	} else {
		*expiredLicenseeLicenses++
	}
}
