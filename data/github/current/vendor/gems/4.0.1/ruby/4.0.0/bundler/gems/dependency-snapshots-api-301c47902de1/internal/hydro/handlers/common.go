package handlers

import (
	"context"
	"reflect"

	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"google.golang.org/protobuf/proto"
)

// Topic names for Hydro envelopes processed by handlers in this package.
const (
	HydroTopicRepositoryPush      = "github.dependencygraph.v1.RepositoryPush"
	HydroTopicEnrollManifests     = "github.dependencygraph.v1.EnrollManifests"
	HydroTopicResetManifests      = "github.dependencygraph.v1.ResetManifests"
	HydroTopicActionsComputeUsage = "github.actions.v0.ComputeUsage"
)

// submitJob enqueues the given job using the provided enqueuer and logs the submission.
func submitJob(
	ctx context.Context,
	logger log.Logger,
	enqueuer aqueduct.Enqueuer,
	job proto.Message,
) error {
	jobName := reflect.TypeOf(job).Elem().Name()
	jobID, err := enqueuer.Enqueue(ctx, job)
	if err != nil {
		return err
	}
	logger.WithFields(
		kvp.String("gh.submitted_job.name", jobName),
		kvp.String("gh.submitted_job.id", jobID),
	).Info("enqueued job")
	return nil
}
