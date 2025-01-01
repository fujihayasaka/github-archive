package eventhandlers

import (
	"context"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	enterprise_accountv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleOrganizationUpgraded handles the OrganizationUpgrade message.
func (eh *EventHandler) HandleOrganizationUpgraded(ctx context.Context, logger log.Logger, message *enterprise_accountv0.OrganizationUpgrade) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	enterpriseCustomerID := message.GetEnterprise().GetCustomerId()
	previousCustomerID := message.GetOrganizationPreviousCustomerId()

	logger = logger.WithFields(
		kvp.Int64("gh.enterprise.customer.id", enterpriseCustomerID),
		kvp.Int64("gh.organization.previous_customer_id", previousCustomerID),
		kvp.Uint64("gh.organization.id", message.GetOrganization().GetId()),
	)
	logger.Info("Begin handle organization upgraded")

	if message.Status != enterprise_accountv0.OrganizationUpgrade_DIRECT_UPGRADED && message.Status != enterprise_accountv0.OrganizationUpgrade_PURCHASE_UPGRADED {
		return Skip{
			reason: "OrganizationUpgrade status not upgraded",
			tags:   stats.Tags{"reason": "org-upgrade-status-ignored"},
		}, Error{}
	}

	jobs := []*models.SyncOrganizationMembershipsJob{}

	if previousCustomerID != 0 {
		jobs = append(jobs, models.NewCustomerSyncJob(uint64(previousCustomerID)))
	}

	if enterpriseCustomerID != previousCustomerID {
		jobs = append(jobs, models.NewCustomerSyncJob(uint64(enterpriseCustomerID)))
	}

	for _, job := range jobs {
		err := eh.queueSyncJob(ctx, logger, job)
		if !err.IsEmpty() {
			err.span = sp
			return Skip{}, err
		}
		logger.Info("sync job queued", kvp.String("gh.licensify.sync_job", fmt.Sprintf("%+v", job)))
	}

	logger.Info("End handle organization upgraded")
	return Skip{}, Error{}
}
