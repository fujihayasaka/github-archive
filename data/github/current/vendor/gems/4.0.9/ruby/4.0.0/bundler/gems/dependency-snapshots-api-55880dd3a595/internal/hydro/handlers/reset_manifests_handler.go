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

// compile-time assertion that ResetManifestsHandler implements hydro.EnvelopeHandler
var _ hydro.EnvelopeHandler = &ResetManifestsHandler{}

type ResetManifestsHandler struct {
	config   *config.Config
	logger   log.Logger
	statter  stats.Client
	enqueuer aqueduct.Enqueuer
}

func NewResetManifestsHandler(
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	enqueuer aqueduct.Enqueuer,
) *ResetManifestsHandler {
	return &ResetManifestsHandler{
		config:   cfg,
		logger:   logger,
		statter:  statter,
		enqueuer: enqueuer,
	}
}

const resetManifestsStatsPrefix = "hydro.consumer.reset_manifests."

func (h *ResetManifestsHandler) HandleEnvelope(ctx context.Context, envelope *hydroclient.Envelope) error {
	coords := hydro.GetKafkaEventCoords(ctx)
	logger := h.logger.WithFields(coords.Fields()...)

	msg := &dependencygraphv1.ResetManifests{}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		h.statter.Counter(resetManifestsStatsPrefix+"dropped_event", stats.Tags{"reason": "unmarshal"}, 1)
		return errors.Wrap(err, "Failed to unmarshal envelope message")
	}

	// extract fields for logging/stats
	requestID := getValidRequestID(msg.GetRequestContext().GetRequestId())
	repoID := uint64(msg.GetRepository().GetId())
	repoVis := msg.GetRepository().GetVisibility()
	actorGlobalID := msg.GetActor().GetGlobalRelayId()
	actorLogin := msg.GetActor().GetLogin()

	// reset-specific fields
	action := msg.GetAction().String()
	trigger := msg.GetTrigger().String()

	logger = logger.WithFields(
		semconv.RequestID(requestID),
		semconv.RepoID(repoID),
		semconv.RepoVisibility(repoVis.String()),
		semconv.ActorGlobalID(actorGlobalID),
		semconv.ActorLogin(actorLogin),
		semconv.ResetManifestsAction(action),
		semconv.ResetManifestsTrigger(trigger),
	)

	statsTags := stats.Tags{
		"action":  action,
		"trigger": trigger,
	}

	payload := resetManifestsPayload{
		requestID: requestID,
		eventID:   coords.EventID,
		msg:       msg,
	}

	switch msg.GetAction() {
	case dependencygraphv1.ResetManifests_RESET_ACTION_CLEAR:
		// At the moment, this will be also done in DGP by enqueuing a DeleteRepositoryJob.
		// However, we need this in case we want to remove DGP's job in the future, i.e.
		// once all source-based analysis is fully retired from DGP.
		err := h.submitExcludeCanonicalSnapshotsJob(ctx, logger, payload)
		if err != nil {
			logger.WithError(err).Error("failed to enqueue job")
			h.statter.Counter(resetManifestsStatsPrefix+"dropped_event",
				statsTags.Merge(
					stats.Tags{"reason": "enqueue_failed"},
				), 1)
			return nil // swallow error to avoid topic getting stuck
		}
	case dependencygraphv1.ResetManifests_RESET_ACTION_REDETECT:
		err := h.submitDependabotSnapshotInitJob(ctx, logger, payload)
		if err != nil {
			logger.WithError(err).Error("failed to enqueue job")
			h.statter.Counter(resetManifestsStatsPrefix+"dropped_event",
				statsTags.Merge(
					stats.Tags{"reason": "enqueue_failed"},
				), 1)
			return nil // swallow error to avoid topic getting stuck
		}
	default:
		logger.Error("unexpected value for ResetManifests Action, ignoring event.")
		h.statter.Counter(resetManifestsStatsPrefix+"dropped_event",
			statsTags.Merge(
				stats.Tags{"reason": "unexpected_action"},
			), 1)
		return nil
	}

	h.statter.Counter(resetManifestsStatsPrefix+"success", statsTags, 1)
	return nil
}

type resetManifestsPayload struct {
	requestID string
	eventID   string
	msg       *dependencygraphv1.ResetManifests
}

// submitDependabotSnapshotInitJob maps the payload from the reset event
// to a DependabotSnapshotInitJob and submits it to the aqueduct enqueuer.
func (h *ResetManifestsHandler) submitDependabotSnapshotInitJob(ctx context.Context, logger log.Logger, p resetManifestsPayload) error {
	defaultBranch := p.msg.GetRepository().GetDefaultBranch()
	if defaultBranch == "" {
		defaultBranch = "main"
	}
	job := &jobs.DependabotSnapshotInitJob{
		RequestId: p.requestID,
		EventId:   p.eventID,
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
		TriggeredBy:     jobs.DependabotSnapshotInitJob_TRIGGERED_BY_RESET,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}

// submitExcludeCanonicalSnapshotsJob maps the payload from the reset event
// to an ExcludeCanonicalSnapshotsJob and submits it to the aqueduct enqueuer.
func (h *ResetManifestsHandler) submitExcludeCanonicalSnapshotsJob(ctx context.Context, logger log.Logger, p resetManifestsPayload) error {
	job := &jobs.ExcludeCanonicalSnapshotsJob{
		RequestId:    p.requestID,
		EventId:      p.eventID,
		RepositoryId: p.msg.GetRepository().GetId(),
		TriggeredBy:  jobs.ExcludeCanonicalSnapshotsJob_TRIGGERED_BY_CLEAR_ACTION,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}
