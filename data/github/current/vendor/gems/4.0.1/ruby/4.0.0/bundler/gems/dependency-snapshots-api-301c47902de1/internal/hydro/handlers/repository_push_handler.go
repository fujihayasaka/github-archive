package handlers

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	dependencygraphv1 "github.com/github/dependency-snapshots-api/hydro/schemas/github/dependencygraph/v1"
	"github.com/github/dependency-snapshots-api/internal/aqueduct"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	"github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/go-stats"
	hydroclient "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	"github.com/pkg/errors"
	"github.com/segmentio/ksuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// compile-time assertion that RepoPushMsgHandler implements hydro.EnvelopeHandler
var _ hydro.EnvelopeHandler = &RepoPushMsgHandler{}

type RepoPushMsgHandler struct {
	config   *config.Config
	logger   log.Logger
	statter  stats.Client
	enqueuer aqueduct.Enqueuer
}

func NewRepositoryPushHandler(
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	enqueuer aqueduct.Enqueuer,
) *RepoPushMsgHandler {
	return &RepoPushMsgHandler{
		config:   cfg,
		logger:   logger,
		statter:  statter,
		enqueuer: enqueuer,
	}
}

const repoPushStatsPrefix = "hydro.consumer.repo_push."

func (h *RepoPushMsgHandler) HandleEnvelope(ctx context.Context, envelope *hydroclient.Envelope) error {
	coords := hydro.GetKafkaEventCoords(ctx)
	logger := h.logger.WithFields(coords.Fields()...)

	msg := &dependencygraphv1.RepositoryPush{}
	if err := proto.Unmarshal(envelope.Message, msg); err != nil {
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "unmarshal"}, 1)
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

	if !h.eligiblePush(msg) {
		logger.Info("skipping event: ineligible push")
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "ineligible_push"}, 1)
		return nil
	}

	defaultRef := fmt.Sprintf("refs/heads/%s", msg.GetRepository().GetDefaultBranch())
	refUpdates, err := h.getRefUpdates(defaultRef, msg)
	if err != nil {
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "is_invalid_oid"}, 1)
		logger.WithError(err).Error("skipping event: invalid object IDs in push")
		return nil
	}
	if len(refUpdates) == 0 {
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "no_ref_updates"}, 1)
		logger.Info("skipping event: no branch diffs found")
		return nil
	}

	// Since we only care about pushes to the default branch, we only expect one job to be enqueued per push event.
	// Therefore, a boolean for stat tracking is sufficient instead of a counter.
	jobEnqueued := false

	// For every ref update in the push, submit a DependabotSnapshot job when eligible
	for _, ref := range refUpdates {
		if !ref.IsDefaultBranch {
			logger.Info("non-default-branch push: skip enqueuing DependabotSnapshot job")
			h.statter.Counter(repoPushStatsPrefix+"ref.skipped", stats.Tags{"reason": "non-default-branch"}, 1)
			continue
		}

		if isRefDeletion(ref.AfterOID) {
			logger.Info("ref deletion: skip enqueuing DependabotSnapshot job")
			h.statter.Counter(repoPushStatsPrefix+"ref.skipped", stats.Tags{"reason": "ref-deletion"}, 1)
			continue
		}

		payload := repositoryPushPayload{
			requestID: requestID,
			coords:    coords,
			msg:       msg,
			ref:       ref,
		}

		isInitPush := isInitPushToRef(ref.BeforeOID)
		if isInitPush {
			err = h.submitDependabotSnapshotInitJob(ctx, logger, payload)
			if err != nil {
				logger.WithFields(
					kvp.String("gh.repo.ref_change.ref_name", ref.RefName),
					kvp.Bool("gh.repo.ref_change.init_push", isInitPush),
				).WithError(err).Error("failed to enqueue job")
				h.statter.Counter(repoPushStatsPrefix+"ref.skipped", stats.Tags{
					"reason": "enqueue_failed",
					"job":    "dependabot_snapshot_init",
				}, 1)
				continue // to next ref update
			}
			jobEnqueued = true
		} else {
			err = h.submitDependabotSnapshotPostPushJob(ctx, logger, payload)
			if err != nil {
				logger.WithFields(
					kvp.String("gh.repo.ref_change.ref_name", ref.RefName),
					kvp.Bool("gh.repo.ref_change.init_push", isInitPush),
				).WithError(err).Error("failed to enqueue job")
				h.statter.Counter(repoPushStatsPrefix+"ref.skipped", stats.Tags{
					"reason": "enqueue_failed",
					"job":    "dependabot_snapshot_post_push",
				}, 1)
				continue // to next ref update
			}
			jobEnqueued = true
		}
	}

	h.statter.Counter(repoPushStatsPrefix+"success", stats.Tags{"enqueued": strconv.FormatBool(jobEnqueued)}, 1)
	return nil
}

// Sentinel Git object IDs used in RepositoryPush events.
const (
	// ZeroOID is a sentinel value for Git object IDs that represents
	// an initial push to a ref, or a deleted ref, in RepositoryPush
	// (beforeOID, afterOID) ranges
	ZeroOID = "0000000000000000000000000000000000000000"
)

type RefUpdate struct {
	BeforeOID       string
	AfterOID        string
	RefName         string
	IsDefaultBranch bool
	PushedAt        time.Time
	PushID          *uint64
}

// Returns true if the system should process the RepositoryPush event
func (h *RepoPushMsgHandler) eligiblePush(msg *dependencygraphv1.RepositoryPush) bool {
	if msg.GetRepository().GetIsArchived() {
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "archived_repo"}, 1)
		h.logger.Warn("push for an archived repository", semconv.RepoID(uint64(msg.GetRepository().GetId())))
		return false
	}

	// TODO: eliminate this after we update monolith side to stop publishing
	// push events for spammy owners, and verify we aren't receiving any more
	if msg.GetOwner().GetSpammy() {
		h.statter.Counter(repoPushStatsPrefix+"dropped_event", stats.Tags{"reason": "spammy_owner"}, 1)
		h.logger.Warn("push by known-spammy repository owner", semconv.OwnerID(uint64(msg.GetOwner().GetId())))
		return false
	}

	return true
}

func (h *RepoPushMsgHandler) getRefUpdates(defaultRef string, msg *dependencygraphv1.RepositoryPush) ([]RefUpdate, error) {
	var result []RefUpdate
	for _, update := range msg.GetRefUpdates() {
		// Skip ref updates which aren't for branches (e.g. tags)
		// See https://github.com/github/dependency-graph/issues/3746 for context.
		if !strings.HasPrefix(update.GetRefName(), "refs/heads/") {
			continue
		}
		newOID := update.GetCurrentRefOid()
		if len(newOID) == 0 {
			return []RefUpdate{}, fmt.Errorf("afterOID is empty for ref %s", update.GetRefName())
		}
		oldOID := update.GetPreviousRefOid()
		if len(oldOID) == 0 {
			return []RefUpdate{}, fmt.Errorf("beforeOID is empty for ref %s", update.GetRefName())
		}
		isDefaultBranch := update.GetRefName() == defaultRef
		// Large diffs can degrade the consumer, so for the time being we trim the diffs.
		// Ignore the cap if the diff is for the default branch, just so we always get those in.
		if len(result) < 100 || isDefaultBranch {
			var pushID *uint64
			if v := update.GetPushId(); v != nil && v.GetValue() > 0 {
				uid := uint64(v.GetValue())
				pushID = &uid
			}
			result = append(result, RefUpdate{
				BeforeOID:       update.GetPreviousRefOid(),
				AfterOID:        update.GetCurrentRefOid(),
				RefName:         update.GetRefName(),
				IsDefaultBranch: isDefaultBranch,
				PushedAt:        update.GetPushedAt().AsTime(),
				PushID:          pushID,
			})
		}
	}
	return result, nil
}

type repositoryPushPayload struct {
	requestID string
	coords    hydro.KafkaEventCoords
	msg       *dependencygraphv1.RepositoryPush
	ref       RefUpdate
}

func (h *RepoPushMsgHandler) submitDependabotSnapshotPostPushJob(ctx context.Context, logger log.Logger, p repositoryPushPayload) error {
	job := &jobs.DependabotSnapshotPostPushJob{
		RequestId: p.requestID,
		EventId:   p.coords.EventID,
		Repository: &jobs.DependabotSnapshotPostPushJob_Repository{
			Id:                  p.msg.GetRepository().GetId(),
			GlobalRelayId:       p.msg.GetRepository().GetGlobalRelayId(),
			Name:                p.msg.GetRepository().GetName(),
			Visibility:          jobs.DependabotSnapshotPostPushJob_Repository_Visibility(p.msg.GetRepository().GetVisibility()),
			ParentId:            p.msg.GetRepository().GetParentId(),
			DefaultBranch:       p.msg.GetRepository().GetDefaultBranch(),
			PrimaryLanguageName: p.msg.GetRepository().GetPrimaryLanguageName(),
		},
		Owner: &jobs.DependabotSnapshotPostPushJob_User{
			Id:            p.msg.GetOwner().GetId(),
			GlobalRelayId: p.msg.GetOwner().GetGlobalRelayId(),
			Login:         p.msg.GetOwner().GetLogin(),
			Type:          jobs.DependabotSnapshotPostPushJob_User_Type(p.msg.GetOwner().GetType()),
		},
		Ref:             p.ref.RefName,
		BeforeOid:       p.ref.BeforeOID,
		AfterOid:        p.ref.AfterOID,
		IsDefaultBranch: p.ref.IsDefaultBranch,
		PushedAt:        timestamppb.New(p.ref.PushedAt),
		IngestedAt:      timestamppb.New(time.Now()),
		TriggeredBy:     jobs.DependabotSnapshotPostPushJob_TRIGGERED_BY_PUSH,
		PushId:          p.ref.PushID,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}

func (h *RepoPushMsgHandler) submitDependabotSnapshotInitJob(ctx context.Context, logger log.Logger, p repositoryPushPayload) error {
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
		Ref:             p.ref.RefName,
		IsDefaultBranch: p.ref.IsDefaultBranch,
		PushedAt:        timestamppb.New(p.ref.PushedAt),
		IngestedAt:      timestamppb.New(time.Now()),
		TriggeredBy:     jobs.DependabotSnapshotInitJob_TRIGGERED_BY_PUSH,
	}
	return submitJob(ctx, logger, h.enqueuer, job)
}

// If request ID is not guaranteed to have a value we need
// something to use downstream. If no ID is detected, this
// helper will generate and return a new identifier for use
// as the request_id value.
func getValidRequestID(requestID string) string {
	if len(requestID) == 0 {
		requestID = ksuid.New().String()
	}
	return requestID
}

func isInitPushToRef(beforeOID string) bool {
	return beforeOID == ZeroOID
}

func isRefDeletion(afterOID string) bool {
	return afterOID == ZeroOID
}
