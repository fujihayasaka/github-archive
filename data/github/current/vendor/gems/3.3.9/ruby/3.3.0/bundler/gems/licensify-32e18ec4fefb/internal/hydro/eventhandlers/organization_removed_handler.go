package eventhandlers

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	enterprise_accountv0 "github.com/github/hydro-schemas-go/hydro/schemas/github/enterprise_account/v0"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleOrganizationRemoved handles the OrganizationRemove message.
func (eh *EventHandler) HandleOrganizationRemoved(ctx context.Context, logger log.Logger, message *enterprise_accountv0.OrganizationRemove) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	customerID := message.GetEnterprise().GetCustomerId()

	logger = logger.WithFields(
		kvp.Uint64("gh.organization.id", message.GetOrganization().GetId()),
		kvp.Int64("gh.enterprise.customer.id", customerID),
	)
	logger.Info("Begin handle organization removed")

	if customerID == 0 {
		return Skip{
			reason: "customer ID is 0",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}

	// When org record is fetched during the sync job, the customer ID will be set
	// to 0 since it's no longer in the enterprise. We can use the enterprise's
	// customer ID to sync the memberships, making sure the org is removed.
	syncJob := models.NewCustomerSyncJob(uint64(customerID))

	err := eh.queueSyncJob(ctx, logger, syncJob)
	if !err.IsEmpty() {
		err.span = sp
		return Skip{}, err
	}

	logger.Info("End handle organization removed")
	return Skip{}, Error{}
}
