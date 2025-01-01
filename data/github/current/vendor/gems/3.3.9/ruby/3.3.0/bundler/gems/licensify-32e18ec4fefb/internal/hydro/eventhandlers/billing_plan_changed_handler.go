package eventhandlers

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleBillingPlanChanged handles the BillingPlanChange message.
func (eh *EventHandler) HandleBillingPlanChanged(ctx context.Context, logger log.Logger, message *githubv1.BillingPlanChange) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	logger = logger.WithFields(
		kvp.Uint64("gh.organization.id", message.GetOrganization().GetId()),
		kvp.String("gh.organization.previous_plan", message.GetPreviousPlan()),
		kvp.String("gh.organization.current_plan", message.GetCurrentPlan()),
	)
	logger.Info("Begin handle billing plan changed")

	if !changeIsUpgradeToTeams(message) {
		return Skip{
			reason: "BillingPlanChange action not upgrade from free plan",
			tags:   stats.Tags{"reason": "org-upgrade-plan-ignored"},
		}, Error{}
	}

	syncJob := models.NewOrganizationSyncJob(message.GetOrganization().GetId())
	err := eh.queueSyncJob(ctx, logger, syncJob)
	if !err.IsEmpty() {
		if !err.IsEmpty() {
			err.span = sp
			return Skip{}, err
		}
	}

	logger.Info("End handle billing plan changed")
	return Skip{}, Error{}
}

func changeIsUpgradeToTeams(message *githubv1.BillingPlanChange) bool {
	return message.GetAction() == githubv1.BillingPlanChange_UPGRADE &&
		message.GetPreviousPlan() == "free" &&
		message.GetCurrentPlan() == "business"
}
