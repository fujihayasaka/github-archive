package eventhandlers

import (
	"context"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	repositoriesv2 "github.com/github/hydro-schemas-go/hydro/schemas/github/repositories/v2"
	"github.com/github/licensify/internal/models"
	"go.opentelemetry.io/otel/trace"
)

// HandleRepositoryRestored processes a repository restored message and queues a job to create repository collaborator enablements.
func (eh *EventHandler) HandleRepositoryRestored(ctx context.Context, logger log.Logger, message *repositoriesv2.Restored) (Skip, Error) {
	sp := trace.SpanFromContext(ctx)

	repoID := uint64(message.RepositoryId)

	logger = logger.WithFields(kvp.Uint64("gh.repository.id", repoID))
	logger.Info("Begin handle repository restored")

	if repoID == 0 {
		return Skip{
			reason: "missing repository id",
			tags:   stats.Tags{"reason": "missing-repository-id"},
		}, Error{}
	}

	job := &models.CreateRepositoryCollaboratorsJob{
		RepositoryID: repoID,
	}
	jobError := eh.queueCreateRepositoryCollaboratorsJob(ctx, logger, job)
	if jobError.Err != nil {
		return Skip{}, Error{
			Err:    jobError.Err,
			origin: jobError.origin,
			span:   sp,
		}
	}

	logger.Info("End handle repository restored")
	return Skip{}, Error{}
}
