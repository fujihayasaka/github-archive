package eventhandlers

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"

	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	aqueductjobs "github.com/github/licensify/internal/aqueduct/jobs"
	"github.com/github/licensify/internal/aqueduct/queues"
	"github.com/github/licensify/internal/models"
	"google.golang.org/protobuf/proto"
)

// getSchemaName returns the last three segments of a hydro message's schema.
func getSchemaName(message proto.Message) string {
	messageFullName := string(message.ProtoReflect().Descriptor().FullName())
	fullNameParts := strings.Split(messageFullName, ".")
	// guard against schema names that contain less than 3 parts
	numParts := min(3, len(fullNameParts))

	return strings.Join(fullNameParts[len(fullNameParts)-numParts:], ".")
}

func (eh *EventHandler) queueSyncJob(ctx context.Context, logger log.Logger, syncJob *models.SyncOrganizationMembershipsJob) Error {
	payload, err := json.Marshal(syncJob)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to marshal sync job: %w", err),
			origin: "marshal-job",
		}
	}

	_, err = eh.jobby.Enqueue(ctx, aqueductjobs.JobNameSyncOrgMemberships, queues.QueueSyncOrgMemberships, payload)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to send job to aqueduct: %w", err),
			origin: "send-job",
		}
	}

	logger.Info("sync job queued", kvp.String("gh.licensify.sync_job", fmt.Sprintf("%+v", syncJob)))

	return Error{}
}

func (eh *EventHandler) queueCreateRepositoryCollaboratorsJob(ctx context.Context, logger log.Logger, job *models.CreateRepositoryCollaboratorsJob) Error {
	payload, err := json.Marshal(job)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to marshal sync job: %w", err),
			origin: "marshal-job",
		}
	}

	jobID, err := eh.jobby.Enqueue(ctx, aqueductjobs.JobNameCreateRepositoryCollaborators, queues.QueueCreateRepositoryCollaborators, payload)
	if err != nil {
		return Error{
			Err:    fmt.Errorf("failed to send job to aqueduct: %w", err),
			origin: "send-job",
		}
	}

	logger.Info("create-repository-collaborators job queued",
		kvp.String("gh.aqueduct.job.id", jobID),
		kvp.String("gh.licensify.job", fmt.Sprintf("%+v", job)),
	)

	return Error{}
}
