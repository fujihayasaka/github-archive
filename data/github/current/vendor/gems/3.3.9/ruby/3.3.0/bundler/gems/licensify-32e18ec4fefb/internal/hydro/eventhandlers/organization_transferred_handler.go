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

// HandleOrganizationTransferred handles the OrganizationTransfer message.
func (eh *EventHandler) HandleOrganizationTransferred(ctx context.Context, logger log.Logger, message *enterprise_accountv0.OrganizationTransfer) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	sourceCustomerID := message.GetSourceEnterprise().GetCustomerId()
	destinationCustomerID := message.GetDestinationEnterprise().GetCustomerId()

	logger = logger.WithFields(
		kvp.Int64("gh.source_enterprise.customer.id", sourceCustomerID),
		kvp.Int64("gh.destination_enterprise.customer.id", destinationCustomerID),
		kvp.Uint64("gh.organization.id", message.GetOrganization().GetId()),
	)
	logger.Info("Begin handle organization transferred")

	if sourceCustomerID == 0 {
		return Skip{
			reason: "source customer ID is 0",
			tags:   stats.Tags{"reason": "missing-source-customer-id"},
		}, Error{}
	}

	if destinationCustomerID == 0 {
		return Skip{
			reason: "destination customer ID is 0",
			tags:   stats.Tags{"reason": "missing-destination-customer-id"},
		}, Error{}
	}

	sourceSyncJob := models.NewCustomerSyncJob(uint64(sourceCustomerID))
	destinationSyncJob := models.NewCustomerSyncJob(uint64(destinationCustomerID))
	jobs := []*models.SyncOrganizationMembershipsJob{
		sourceSyncJob,
		destinationSyncJob,
	}

	for _, job := range jobs {
		err := eh.queueSyncJob(ctx, logger, job)
		if !err.IsEmpty() {
			err.span = sp
			return Skip{}, err
		}
		logger.Info("sync job queued", kvp.String("gh.licensify.sync_job", fmt.Sprintf("%+v", job)))
	}

	logger.Info("End handle organization transferred")
	return Skip{}, Error{}
}
