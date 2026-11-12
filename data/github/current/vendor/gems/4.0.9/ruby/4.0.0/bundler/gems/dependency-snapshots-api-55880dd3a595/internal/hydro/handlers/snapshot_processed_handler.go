package handlers

import (
	"context"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
)

// compile-time assertion
var _ hydro.EnvelopeHandler = &SnapshotProcessedHandler{}

const snapshotProcessedStatsPrefix = "hydro.consumer.snapshot_processed."

// SnapshotProcessedHandler consumes SnapshotProcessed events and enqueues
// denormalization jobs for snapshots that changed canonical dependencies.
type SnapshotProcessedHandler struct {
	logger   log.Logger
	statter  stats.Client
	enqueuer aqueduct.Enqueuer
}

// NewSnapshotProcessedHandler creates a new SnapshotProcessedHandler.
func NewSnapshotProcessedHandler(
	logger log.Logger,
	statter stats.Client,
	enqueuer aqueduct.Enqueuer,
) *SnapshotProcessedHandler {
	return &SnapshotProcessedHandler{
		logger:   logger,
		statter:  statter,
		enqueuer: enqueuer,
	}
}

func (h *SnapshotProcessedHandler) HandleEnvelope(ctx context.Context, envelope *hydroclient.Envelope) error {
	coords := hydro.GetKafkaEventCoords(ctx)
	logger := h.logger.WithFields(coords.Fields()...)

	msg := &dependencygraphv1.SnapshotProcessed{}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		h.statter.Counter(snapshotProcessedStatsPrefix+"dropped_event", stats.Tags{"reason": "unmarshal"}, 1)
		return errors.Wrap(err, "failed to unmarshal SnapshotProcessed message")
	}

	repoID := uint64(msg.GetRepositoryId())
	logger = logger.WithFields(semconv.RepoID(repoID))

	// Only denormalize when the snapshot actually changed canonical dependencies.
	if msg.DependencyChange == nil || !msg.DependencyChange.GetValue() {
		h.statter.Counter(snapshotProcessedStatsPrefix+"skipped", stats.Tags{}, 1)
		logger.Debug("skipping: dependency_change is not true")
		return nil
	}

	job := &jobsproto.DenormalizeSnapshotDependenciesJob{
		RepositoryId: repoID,
	}

	if err := submitJob(ctx, logger, h.enqueuer, job); err != nil {
		h.statter.Counter(snapshotProcessedStatsPrefix+"enqueue_error", stats.Tags{}, 1)
		return errors.Wrap(err, "failed to enqueue denormalization job")
	}

	h.statter.Counter(snapshotProcessedStatsPrefix+"enqueued", stats.Tags{}, 1)
	return nil
}
