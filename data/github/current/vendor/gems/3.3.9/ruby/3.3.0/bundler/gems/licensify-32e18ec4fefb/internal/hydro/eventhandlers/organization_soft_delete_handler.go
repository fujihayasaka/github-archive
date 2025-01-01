package eventhandlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	githubv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/v1"
	aqueductjobs "github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleOrganizationSoftDelete handles the OrganizationSoftDelete message.
func (eh *EventHandler) HandleOrganizationSoftDelete(ctx context.Context, logger log.Logger, message *githubv1.OrganizationSoftDelete) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	organizationID := message.GetOrganization().GetId()
	customerID := message.GetCustomerId()

	logger = logger.WithFields(
		kvp.Int64("gh.customer.id", customerID),
		kvp.Uint64("gh.organization.id", organizationID),
	)
	logger.Info("Begin handle organization soft delete")

	if customerID == 0 {
		return Skip{reason: "customer ID is 0", tags: stats.Tags{"reason": "missing-customer-id"}}, Error{}
	}
	if organizationID == 0 {
		return Skip{reason: "organization ID is 0", tags: stats.Tags{"reason": "missing-organization-id"}}, Error{}
	}

	jobError := eh.queueDeleteEnablementsJob(ctx, &models.DeleteEnablementsJob{
		CustomerID:       uint64(customerID),
		EnablementReason: models.EnablementReasonOrgMembership,
		EnablementID:     organizationID,
	})

	logger.Info("End handle organization soft delete")
	return Skip{}, Error{
		Err:    jobError.Err,
		origin: jobError.origin,
		span:   sp,
	}
}

func (eh *EventHandler) queueDeleteEnablementsJob(ctx context.Context, job *models.DeleteEnablementsJob) Error {
	payload, err := json.Marshal(job)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to marshal sync job: %w", err),
			origin: "marshal-job",
		}
	}

	_, err = eh.jobby.Enqueue(ctx, aqueductjobs.JobNameDeleteEnablements, queues.QueueDeleteEnablements, payload)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to send job to aqueduct: %w", err),
			origin: "send-job",
		}
	}

	return Error{}
}
