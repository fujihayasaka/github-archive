package handlers

import (
	"context"
	"time"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// compile-time assertion that EnrollManifestsHandler implements hydro.EnvelopeHandler
var _ hydro.EnvelopeHandler = &EnrollManifestsHandler{}

type EnrollManifestsHandler struct {
	config   *config.Config
	logger   log.Logger
	statter  stats.Client
	enqueuer aqueduct.Enqueuer
}

func NewEnrollManifestsHandler(
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	enqueuer aqueduct.Enqueuer,
) *EnrollManifestsHandler {
	return &EnrollManifestsHandler{
		config:   cfg,
		logger:   logger,
		statter:  statter,
		enqueuer: enqueuer,
	}
}

const enrollManifestsStatsPrefix = "hydro.consumer.enroll_manifests."

func (h *EnrollManifestsHandler) HandleEnvelope(ctx context.Context, envelope *hydroclient.Envelope) error {
	coords := hydro.GetKafkaEventCoords(ctx)
	logger := h.logger.WithFields(coords.Fields()...)

	msg := &dependencygraphv1.EnrollManifests{}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		h.statter.Counter(enrollManifestsStatsPrefix+"dropped_event", stats.Tags{"reason": "unmarshal"}, 1)
		return errors.Wrap(err, "Failed to unmarshal envelope message")
	}

	// extract fields for logging/stats
	requestID := getValidRequestID(msg.GetRequestContext().GetRequestId())
	repoID := uint64(msg.GetRepository().GetId())
	repoVis := msg.GetRepository().GetVisibility()
	actorGlobalID := msg.GetActor().GetGlobalRelayId()
	actorLogin := msg.GetActor().GetLogin()

	logger = logger.WithFields(
		semconv.RequestID(requestID),
		semconv.RepoID(repoID),
		semconv.RepoVisibility(repoVis.String()),
		semconv.ActorGlobalID(actorGlobalID),
		semconv.ActorLogin(actorLogin),
	)

	payload := enrollManifestsPayload{
		requestID: requestID,
		coords:    coords,
		msg:       msg,
	}

	err := h.submitDependabotSnapshotInitJob(ctx, logger, payload)
	if err != nil {
		logger.WithError(err).Error("failed to enqueue job")
		h.statter.Counter(enrollManifestsStatsPrefix+"dropped_event", stats.Tags{"reason": "enqueue_failed"}, 1)
		return nil // swallow error to avoid topic getting stuck
	}

	h.statter.Counter(enrollManifestsStatsPrefix+"success", nil, 1)
	return nil
}

type enrollManifestsPayload struct {
	requestID string
	coords    hydro.KafkaEventCoords
	msg       *dependencygraphv1.EnrollManifests
}

func (h *EnrollManifestsHandler) submitDependabotSnapshotInitJob(ctx context.Context, logger log.Logger, p enrollManifestsPayload) error {
	defaultBranch := p.msg.GetRepository().GetDefaultBranch()
	if defaultBranch == "" {
		defaultBranch = "main"
	}
	job := &jobs.DependabotSnapshotInitJob{
		RequestId: p.requestID,
		EventId:   p.coords.EventID,
		Repository: &jobs.DependabotSnapshotInitJob_Repository{
			Id:                  p.msg.GetRepository().GetId(),
			GlobalRelayId:       p.msg.GetRepository().GetGlobalRelayId(),
			Name:                p.msg.GetRepository().GetName(),
			Visibility:          jobs.DependabotSnapshotInitJob_Repository_Visibility(p.msg.GetRepository().GetVisibility()),
			ParentId:            p.msg.GetRepository().GetParentId(),
			DefaultBranch:       p.msg.GetRepository().GetDefaultBranch(),
			PrimaryLanguageName: p.msg.GetRepository().GetPrimaryLanguageName(),
		},
		Owner: &jobs.DependabotSnapshotInitJob_User{
			Id:            p.msg.GetOwner().GetId(),
			GlobalRelayId: p.msg.GetOwner().GetGlobalRelayId(),
			Login:         p.msg.GetOwner().GetLogin(),
			Type:          jobs.DependabotSnapshotInitJob_User_Type(p.msg.GetOwner().GetType()),
		},
		Ref:             "refs/heads/" + defaultBranch,
		IsDefaultBranch: true,
		IngestedAt:      timestamppb.New(time.Now()),
		TriggeredBy:     jobs.DependabotSnapshotInitJob_TRIGGERED_BY_ENROLLMENT,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}
