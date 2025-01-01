package eventhandlers

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/models"
)

// HandleOrganizationRestore handles the OrganizationRestore message.
func (eh *EventHandler) HandleOrganizationRestore(ctx context.Context, logger log.Logger, message *githubv1.OrganizationRestore) (Skip, Error) {
	organizationID := message.GetOrganization().GetId()

	logger = logger.WithFields(
		kvp.Uint64("gh.organization.id", organizationID),
		kvp.Int64("gh.enterprise.customer.id", message.GetCustomerId()),
	)
	logger.Info("Begin handle organization restore")

	if organizationID == 0 {
		return Skip{
			reason: "organization ID is 0",
			tags:   stats.Tags{"reason": "missing-organization-id"},
		}, Error{}
	}

	err := eh.queueSyncJob(ctx, logger, models.NewOrganizationSyncJob(organizationID))
	if !err.IsEmpty() {
		return Skip{}, err
	}

	logger.Info("End handle organization restore")
	return Skip{}, Error{}
}
