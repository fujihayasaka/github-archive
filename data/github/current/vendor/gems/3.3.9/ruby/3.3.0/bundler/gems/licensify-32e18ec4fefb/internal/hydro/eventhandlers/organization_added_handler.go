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

// HandleOrganizationAdded handles the OrganizationAdd message.
func (eh *EventHandler) HandleOrganizationAdded(ctx context.Context, logger log.Logger, message *enterprise_accountv0.OrganizationAdd) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	customerID := message.GetEnterprise().GetCustomerId()

	logger = logger.WithFields(
		kvp.Uint64("gh.organization.id", message.GetOrganization().GetId()),
		kvp.Int64("gh.enterprise.customer.id", customerID),
	)
	logger.Info("Begin handle organization added")

	// Sync customer instead of single org. We can't sync collaborators on a single org right now
	// because we don't know which repos should be deleted off the license due to no longer
	// existing in the org vs being part of a different org
	if customerID == 0 {
		return Skip{
			reason: "customer ID is 0",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}

	customerSyncJob := models.NewCustomerSyncJob(uint64(customerID))

	err := eh.queueSyncJob(ctx, logger, customerSyncJob)
	if !err.IsEmpty() {
		err.span = sp
		return Skip{}, err
	}

	logger.Info("End handle organization added")
	return Skip{}, Error{}
}
