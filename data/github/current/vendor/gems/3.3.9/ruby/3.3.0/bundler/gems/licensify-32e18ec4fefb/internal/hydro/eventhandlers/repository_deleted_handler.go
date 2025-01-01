package eventhandlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	ghrepositoriesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v1"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/models"
	repositoriesv1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
)

// HandleRepositoryDeleted processes a repository deleted message and queues a job to delete the enablements for the repo.
func (eh *EventHandler) HandleRepositoryDeleted(ctx context.Context, logger log.Logger, message *ghrepositoriesv1.Deleted) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	repoID := uint64(message.RepositoryId)

	logger = logger.WithFields(kvp.Uint64("gh.repository.id", repoID))
	logger.Info("Begin handle repository deleted")

	if repoID == 0 {
		return Skip{
			reason: "missing repository id",
			tags:   stats.Tags{"reason": "missing-repository-id"},
		}, Error{}
	}

	repoReq := &repositoriesv1.GetRepositoryInformationRequest{
		Id: uint64(message.RepositoryId),
	}
	repoInfo, err := eh.monolithClient.GetRepositoryInformation(ctx, repoReq)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to get repository from monolith with request %+v: %w", repoReq, err),
			origin: "get-repo-info",
			span:   sp,
		}
	}

	customerID := uint64(repoInfo.GetRepository().GetOwnerCustomerId())

	logger = logger.WithFields(kvp.Uint64("gh.customer.id", customerID))
	logger.Info("Fetched repository owner customer id")

	if customerID == 0 {
		return Skip{
			reason: "missing customer id for repository",
			tags:   stats.Tags{"reason": "missing-customer-id"},
		}, Error{}
	}

	job := &models.DeleteEnablementsJob{
		CustomerID:       customerID,
		EnablementReason: models.EnablementReasonRepositoryCollaborator,
		EnablementID:     repoID,
	}
	payload, err := json.Marshal(job)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to marshal delete enablements job: %w", err),
			origin: "marshal-job",
			span:   sp,
		}
	}

	jobID, err := eh.jobby.Enqueue(ctx, jobs.JobNameDeleteEnablements, queues.QueueDeleteEnablements, payload)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to send job to aqueduct: %w", err),
			origin: "send-job",
			span:   sp,
		}
	}

	logger.Info("delete-enablements job queued",
		kvp.String("gh.aqueduct.job.id", jobID),
		kvp.String("gh.licensify.job", fmt.Sprintf("%+v", job)),
	)

	logger.Info("End handle repository deleted")
	return Skip{}, Error{}
}
