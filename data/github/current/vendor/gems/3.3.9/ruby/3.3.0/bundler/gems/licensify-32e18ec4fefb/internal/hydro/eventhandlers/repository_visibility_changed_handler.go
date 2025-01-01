package eventhandlers

import (
	"context"
	"encoding/json"
	"fmt"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/go-stats"
	hydroRepositoriesv1 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v1"
	"github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/models"
	repositoriesApiV1 "github.com/github/licensify/lib/monolith-twirp/repositories/v1"
)

// HandleRepoVisibilityChanged handles the RepositoryVisibilityChanged message.
func (eh *EventHandler) HandleRepoVisibilityChanged(ctx context.Context, logger log.Logger, message *hydroRepositoriesv1.VisibilityChanged) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	repositoryID := uint64(message.GetRepositoryId())

	logger = logger.WithFields(
		kvp.Uint64("gh.hydro.msg.repository.id", repositoryID),
	)
	logger.Info("Begin handle repository visibility changed")

	if repositoryID == 0 {
		return Skip{reason: "repository ID is 0", tags: stats.Tags{"reason": "missing-repository-id"}}, Error{}
	}

	req := &repositoriesApiV1.GetRepositoryInformationRequest{Id: repositoryID}
	res, err := eh.monolithClient.GetRepositoryInformation(ctx, req)
	if err != nil {
		return Skip{}, Error{
			Err:    fmt.Errorf("failed to get repository from monolith with request %+v: %w", req, err),
			origin: "get-repository",
			span:   sp,
		}
	}

	repository := &models.Repository{
		ID:                  repositoryID,
		Visibility:          models.RepositoryVisibility(message.GetNewVisibility().Number()),
		ParentID:            res.GetRepository().GetParentId(),
		CustomerID:          uint64(res.GetRepository().GetOwnerCustomerId()),
		IsAdvisoryWorkspace: res.GetRepository().GetIsAdvisoryWorkspace(),
		IsFork:              res.GetRepository().GetIsFork(),
		IsActive:            res.GetRepository().GetIsActive(),
	}

	if repository.MissingRequiredIDs() {
		return Skip{reason: "unable to process repository", tags: stats.Tags{"reason": "unable-to-process"}}, Error{}
	}
	if !repository.IsActive {
		return Skip{reason: "repository is not active", tags: stats.Tags{"reason": "repository-not-active"}}, Error{}
	}

	logger = logger.WithFields(
		kvp.Uint64("gh.hydro.msg.customer.id", repository.CustomerID),
	)

	if repository.VisibilityConsumesLicenses() {
		job := &models.CreateRepositoryCollaboratorsJob{RepositoryID: repository.ID}
		if err := eh.queueCreateRepositoryCollaboratorsJob(ctx, logger, job); !err.IsEmpty() {
			return Skip{}, Error{
				Err:    fmt.Errorf("failed to handle private/internal visibility: %w", err.Err),
				origin: err.origin,
				span:   sp,
			}
		}
	} else if repository.IsPublic() {
		if err := eh.handleRepoPublicVisibility(ctx, logger, repository); !err.IsEmpty() {
			return Skip{}, Error{
				Err:    fmt.Errorf("failed to handle public visibility: %w", err.Err),
				origin: err.origin,
				span:   sp,
			}
		}
	}

	logger.Info("End handle repository visibility changed")
	return Skip{}, Error{}
}

func (eh *EventHandler) handleRepoPublicVisibility(ctx context.Context, logger log.Logger, repository *models.Repository) Error {
	job := &models.DeleteEnablementsJob{
		CustomerID:       repository.CustomerID,
		EnablementReason: models.EnablementReasonRepositoryCollaborator,
		EnablementID:     repository.ID,
	}

	payload, err := json.Marshal(job)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to marshal job: %w", err),
			origin: "marshal-job",
		}
	}

	jobID, err := eh.jobby.Enqueue(ctx, jobs.JobNameDeleteEnablements, queues.QueueDeleteEnablements, payload)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to send job to aqueduct: %w", err),
			origin: "send-job",
		}
	}

	logger.Info("delete-enablements job queued",
		kvp.String("gh.aqueduct.job.id", jobID),
		kvp.String("gh.licensify.job", fmt.Sprintf("%+v", job)),
	)

	return Error{}
}
