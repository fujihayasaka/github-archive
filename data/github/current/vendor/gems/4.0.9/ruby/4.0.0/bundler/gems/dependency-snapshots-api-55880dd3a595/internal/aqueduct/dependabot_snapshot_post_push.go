package aqueduct

import (
	"context"
	"fmt"
	"slices"
	"strconv"
	"time"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0"
	"github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0/entities"
	"github.com/github/dependency-snapshots-api/internal/aqueduct/manifests"
	"github.com/github/dependency-snapshots-api/internal/config"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/features"
	"github.com/github/dependency-snapshots-api/internal/gitaccess"
	"github.com/github/dependency-snapshots-api/internal/hydro"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/semconv"
	jobsproto "github.com/github/dependency-snapshots-api/pkg/proto/jobs"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/github-telemetry-go/log"
	"github.com/github/github-telemetry-go/trace"
	"github.com/github/go-http/v2/middleware/tenant"
	"github.com/github/go-stats"
	"github.com/pkg/errors"
	"google.golang.org/protobuf/types/known/timestamppb"
)

const (
	ParseOnceGoFeatureFlag        = "dependency_graph_parses_golang_once"
	ParseOnceNPMFeatureFlag       = "dependency_graph_parses_npm_once"
	ParseOncePythonFeatureFlag    = "dependency_graph_parses_python_once"
	snapshotJobMetricPrefix       = "aqueduct.handler.dependabot_snapshot_post_push."
	RepositoryAlertingFeatureFlag = "dependency_graph_parse_once_repository_alerting"
	// TODO(brrygrdn): Revise default deadline
	//
	// This is set once for both init and push, but we should tune it separately for each event.
	defaultDependabotSnapshotDeadlinePeriod = 30 * time.Minute
)

type GraphChange struct {
	Ecosystem ecosystems.Ecosystem
	Path      string
}

type Repository struct {
	ID              uint64
	GlobalRelayID   string
	Name            string
	Visibility      int32
	ParentID        uint32
	DefaultBranch   string
	PrimaryLanguage string
}

type Owner struct {
	ID            uint64
	GlobalRelayID string
	Login         string
	Type          int32
	DecodedType   OwnerType
}

type OwnerType int

const (
	OwnerTypeUnknown OwnerType = iota
	OwnerTypeUser
	OwnerTypeOrganization
)

type snapshotJobData struct {
	RequestID       string
	EventID         string
	Repository      Repository
	Owner           Owner
	Ref             string
	IsDefaultBranch bool
	TriggeredBy     string
	PushedAt        *timestamppb.Timestamp
	IngestedAt      *timestamppb.Timestamp
	PushID          *uint64
}

func HandleDependabotSnapshotPostReceiveJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	tracer *trace.Tracer,
	gitClient gitaccess.Client,
	publisher hydro.Publisher,
	ffClient features.Client,
	dependabotEventSvc interfaces.DependabotEventService,
	job *jobsproto.DependabotSnapshotPostPushJob,
) error {
	repoID := uint64(job.GetRepository().GetId())
	triggeredBy := job.GetTriggeredBy()

	logFields := []kvp.Field{
		semconv.RequestID(job.GetRequestId()),
		semconv.MessagingMessageID(job.GetEventId()),
		semconv.RepoID(repoID),
		semconv.GitRef(job.GetRef()),
		semconv.GitPushBeforeOid(job.GetBeforeOid()),
		semconv.GitPushAfterOid(job.GetAfterOid()),
		semconv.IsDefaultBranch(job.GetIsDefaultBranch()),
		semconv.JobTriggeredBy(triggeredBy.String()),
		tenant.GetTenantField(ctx),
		tenant.GetTenantIDField(ctx),
	}
	logger = logger.WithFields(logFields...)

	tags := stats.Tags{
		"triggered_by": triggeredBy.String(),
		"init_push":    strconv.FormatBool(false), // Always false for this handler
	}

	// skip for invalid repos
	if repoID == 0 {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: invalid repository")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "invalid_repo"}), 1)
		return nil
	}

	// initially only running for default branch pushes
	if !job.IsDefaultBranch {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: triggered by non-default branch push")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "non_default_branch"}), 1)
		return nil
	}

	// we don't process deleted refs
	if job.GetAfterOid() == manifests.ZeroOID {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: after OID indicates deleted ref")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "deleted_ref"}), 1)
		return nil
	}

	// we shouldn't receive an init push here, but double check
	if job.GetBeforeOid() == manifests.ZeroOID {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: before OID indicates init push")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "init_push"}), 1)
		return nil
	}

	jobData := extractPostReceiveJobData(job)
	ecos, err := enabledEcosystems(ctx, ffClient, repoID, jobData.Owner)
	if err != nil {
		logger.WithError(err).Error("DependabotSnapshotPostReceiveJob failed to determine feature flagged ecosystems", semconv.RepoID(repoID))
		statter.Counter(snapshotJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "feature_flag_check"}), 1)
		return errors.Wrap(err, "failed to determine feature flagged ecosystems")
	}

	if len(ecos) == 0 {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: no ecosystems enabled for repo")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "no_ecosystems_enabled"}), 1)

		// Notify the monolith to hand off processing to legacy manifest detection
		if err := publishDependabotEventFallback(ctx, publisher, ffClient, logger, statter, repoID, jobData.Owner, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, jobData.RequestID, jobData.Ref, job.GetAfterOid()); err != nil {
			return errors.Wrap(err, "failed to publish DependabotEventProcessed")
		}

		return nil
	}

	// enumerate & classify content changes in the push changeset
	enumerator := manifests.NewChangesetEnumerator(cfg, tracer, statter, gitClient)

	// TODO: refactor the changeset enumerator to be more generic
	// For now, we construct a ManifestChangesetJob payload to satisfy the interface
	payload := &jobsproto.ManifestChangesetJob{
		RequestId:    job.RequestId,
		EventId:      job.EventId,
		RepositoryId: repoID,
		BeforeOid:    job.GetBeforeOid(),
		AfterOid:     job.GetAfterOid(),
	}
	groupedManifests, err := enumerator.Process(ctx, payload)
	if err != nil {
		logger.WithError(err).Error("DependabotSnapshotPostReceiveJob failed to enumerate and classify repository content from push changeset", semconv.RepoID(repoID))
		statter.Counter(snapshotJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "enumerator"}), 1)
		return errors.Wrap(err, "failed to enumerate and classify repository content from push changeset")
	}

	// Collect graph changes from manifests
	graphChanges := collectGraphChanges(groupedManifests, ecos)

	if len(graphChanges) == 0 {
		logger.Info("DependabotSnapshotPostReceiveJob skipped: no relevant manifest changes detected")
		statter.Counter(snapshotJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "no_manifest_changes"}), 1)

		// Notify the monolith to hand off processing to legacy manifest detection
		if err := publishDependabotEventFallback(ctx, publisher, ffClient, logger, statter, repoID, jobData.Owner, hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH, jobData.RequestID, jobData.Ref, job.GetAfterOid()); err != nil {
			return errors.Wrap(err, "failed to publish DependabotEventProcessed")
		}

		return nil
	}

	// Record the event so we know which snapshots we need to wait on
	eventID, err := recordDependabotEvent(ctx, ffClient, dependabotEventSvc, logger, statter, repoID, jobData.Owner, interfaces.EventTypePush, jobData.Ref, job.GetAfterOid(), jobData.PushID, graphChanges)
	if err != nil {
		statter.Counter(snapshotJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "record_event"}), 1)
		return errors.Wrap(err, "failed to record dependabot event")
	}

	// Build and publish the UpdateGraphEvent
	graphPayload := buildPayload(jobData, graphChanges, eventID)
	if err := publishGraphChanges(ctx, publisher, graphPayload, logger, statter, tags, snapshotJobMetricPrefix); err != nil {
		return errors.Wrap(err, "failed to publish graph changes")
	}

	// Notify the monolith that processing is complete
	if err := publishDependabotEventProcessed(ctx, publisher, ffClient, logger, statter, dependabotEventProcessedMsg{
		RepoID:    repoID,
		Owner:     jobData.Owner,
		EventID:   eventID,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_PUSH,
		Ref:       jobData.Ref,
		SHA:       job.GetAfterOid(),
		PushID:    jobData.PushID,
		RequestID: jobData.RequestID,
	}); err != nil {
		return errors.Wrap(err, "failed to publish DependabotEventProcessed")
	}

	// Emit latency metrics
	emitLatencyMetrics(jobData.PushedAt, jobData.IngestedAt, statter, tags)

	return nil
}

func extractRepositoryFromPostReceive(repo *jobsproto.DependabotSnapshotPostPushJob_Repository) Repository {
	return Repository{
		ID:              uint64(repo.GetId()),
		GlobalRelayID:   repo.GetGlobalRelayId(),
		Name:            repo.GetName(),
		Visibility:      int32(repo.GetVisibility()),
		ParentID:        repo.GetParentId(),
		DefaultBranch:   repo.GetDefaultBranch(),
		PrimaryLanguage: repo.GetPrimaryLanguageName(),
	}
}

func extractOwnerFromPostReceive(user *jobsproto.DependabotSnapshotPostPushJob_User) Owner {
	var ownerType OwnerType
	switch user.GetType() {
	case jobsproto.DependabotSnapshotPostPushJob_User_TYPE_USER:
		ownerType = OwnerTypeUser
	case jobsproto.DependabotSnapshotPostPushJob_User_TYPE_ORGANIZATION:
		ownerType = OwnerTypeOrganization
	default:
		ownerType = OwnerTypeUnknown
	}

	return Owner{
		ID:            uint64(user.GetId()),
		GlobalRelayID: user.GetGlobalRelayId(),
		Login:         user.GetLogin(),
		Type:          int32(user.GetType()),
		DecodedType:   ownerType,
	}
}

func extractPostReceiveJobData(job *jobsproto.DependabotSnapshotPostPushJob) snapshotJobData {
	var pushID *uint64
	if job.PushId != nil {
		v := job.GetPushId()
		pushID = &v
	}
	return snapshotJobData{
		RequestID:       job.GetRequestId(),
		EventID:         job.GetEventId(),
		Repository:      extractRepositoryFromPostReceive(job.GetRepository()),
		Owner:           extractOwnerFromPostReceive(job.GetOwner()),
		Ref:             job.GetRef(),
		IsDefaultBranch: job.GetIsDefaultBranch(),
		TriggeredBy:     job.GetTriggeredBy().String(),
		PushedAt:        job.GetPushedAt(),
		IngestedAt:      job.GetIngestedAt(),
		PushID:          pushID,
	}
}

// collectGraphChanges maps grouped manifests to graph changes filtered by enabled ecosystems
func collectGraphChanges(groupedManifests manifests.RelatedManifests, ecos []ecosystems.Ecosystem) map[GraphChange]struct{} {
	graphChanges := make(map[GraphChange]struct{})

	// map grouped manifests by ecosystem and path for updates
	for _, manifestChanges := range groupedManifests.ToUpdate {
		if len(manifestChanges) == 0 {
			continue
		}
		// first item of related manifests should be sufficient to identify the group
		ecosystem := manifestChanges[0].FileInfo.Ecosystem
		path := manifestChanges[0].FileInfo.Path
		if slices.Contains(ecos, ecosystem) {
			graphChanges[GraphChange{Ecosystem: ecosystem, Path: path}] = struct{}{}
		}
	}

	// map grouped manifests by ecosystem and path for deletions
	for _, manifestChange := range groupedManifests.ToDelete {
		ecosystem := manifestChange.FileInfo.Ecosystem
		path := manifestChange.FileInfo.Path
		if slices.Contains(ecos, ecosystem) {
			graphChanges[GraphChange{Ecosystem: ecosystem, Path: path}] = struct{}{}
		}
	}

	return graphChanges
}

// enabledEcosystems returns the set of ecosystems gated by feature flags for a repository/owner.
// Only Go and NPM are supported currently, each behind its own flag.
func enabledEcosystems(ctx context.Context, ffClient features.Client, repoID uint64, owner Owner) ([]ecosystems.Ecosystem, error) {
	enabled := make([]ecosystems.Ecosystem, 0)

	goEnabled, err := isFeatureEnabled(ctx, ffClient, ParseOnceGoFeatureFlag, repoID, owner)
	if err != nil {
		return nil, fmt.Errorf("failed to check feature flag: %w", err)
	}
	if goEnabled {
		enabled = append(enabled, ecosystems.Golang)
	}

	npmEnabled, err := isFeatureEnabled(ctx, ffClient, ParseOnceNPMFeatureFlag, repoID, owner)
	if err != nil {
		return nil, fmt.Errorf("failed to check feature flag: %w", err)
	}
	if npmEnabled {
		enabled = append(enabled, ecosystems.NPM)
	}

	pythonEnabled, err := isFeatureEnabled(ctx, ffClient, ParseOncePythonFeatureFlag, repoID, owner)
	if err != nil {
		return nil, fmt.Errorf("failed to check feature flag: %w", err)
	}
	if pythonEnabled {
		enabled = append(enabled, ecosystems.PyPi)
	}

	return enabled, nil
}

// checks if a feature is enabled for a repo, if not checks the owner (user/org)
func isFeatureEnabled(ctx context.Context, ffClient features.Client, feature string, repoID uint64, owner Owner) (bool, error) {
	enabled, err := ffClient.IsFeatureFlagEnabledForRepository(ctx, feature, repoID)
	if err != nil {
		return false, fmt.Errorf("failed to check feature flag: %w", err)
	}

	if enabled {
		return true, nil
	}

	// if not enabled for repo, check if enabled for owner (user/org)
	switch owner.DecodedType {
	case OwnerTypeUser:
		enabled, err = ffClient.IsFeatureFlagEnabledForUser(ctx, feature, owner.ID)
	case OwnerTypeOrganization:
		enabled, err = ffClient.IsFeatureFlagEnabledForOrganization(ctx, feature, owner.ID)
	default:
		enabled = false
		err = nil
	}
	if err != nil {
		return false, fmt.Errorf("failed to check feature flag: %w", err)
	}

	return enabled, nil
}

// buildPayload constructs an UpdateGraphEvent proto from job data and graph changes.
func buildPayload(jobData snapshotJobData, changes map[GraphChange]struct{}, eventID uint64) *hydroproto.UpdateGraphEvent {
	payload := &hydroproto.UpdateGraphEvent{
		RequestId: jobData.RequestID,
		EventId:   eventID,
		Repository: &hydroproto.UpdateGraphEvent_Repository{
			Id:            uint32(jobData.Repository.ID),
			GlobalRelayId: jobData.Repository.GlobalRelayID,
			Name:          jobData.Repository.Name,
			// This is identical to the visibility enum in the job proto so the cast is safe
			Visibility:          hydroproto.UpdateGraphEvent_Repository_Visibility(jobData.Repository.Visibility),
			ParentId:            jobData.Repository.ParentID,
			DefaultBranch:       jobData.Repository.DefaultBranch,
			PrimaryLanguageName: jobData.Repository.PrimaryLanguage,
		},
		Owner: &hydroproto.UpdateGraphEvent_User{
			Id:            uint32(jobData.Owner.ID),
			GlobalRelayId: jobData.Owner.GlobalRelayID,
			Login:         jobData.Owner.Login,
			// This is identical to the type enum in the job proto so the cast is safe
			Type: hydroproto.UpdateGraphEvent_User_Type(jobData.Owner.Type),
		},
		GraphChanges: make([]*hydroproto.UpdateGraphEvent_GraphChange, 0, len(changes)),
		// Use the current time as the request time
		RequestedAt: timestamppb.New(time.Now()),
	}
	for change := range changes {
		payload.GraphChanges = append(payload.GraphChanges, &hydroproto.UpdateGraphEvent_GraphChange{
			RefName:   jobData.Ref,
			Ecosystem: ecosystemToProto(change.Ecosystem),
			Directory: change.Path,
		})
	}
	return payload
}

// publishGraphChanges publishes the UpdateGraphEvent and emits success metrics.
func publishGraphChanges(ctx context.Context, publisher hydro.Publisher, payload *hydroproto.UpdateGraphEvent, logger log.Logger, statter stats.Client, tags stats.Tags, metricPrefix string) error {
	err := publisher.Publish(ctx, payload)
	if err != nil {
		logger.WithError(err).Error("Failed to publish UpdateGraphEvent")
		statter.Counter(metricPrefix+"error", tags.Merge(stats.Tags{"reason": "publish_failed"}), 1)
		return errors.Wrap(err, "failed to publish UpdateGraphEvent")
	}

	// emit success metrics
	statter.Distribution(metricPrefix+"graph_changes", tags, float64(len(payload.GraphChanges)))
	statter.Counter(metricPrefix+"success", tags, 1)

	return nil
}

// ecosystemToProto maps an internal ecosystem type to the proto Ecosystem enum.
func ecosystemToProto(e ecosystems.Ecosystem) entities.Ecosystem {
	switch e {
	case ecosystems.Golang:
		return entities.Ecosystem_ECOSYSTEM_GO
	case ecosystems.NPM:
		return entities.Ecosystem_ECOSYSTEM_NPM
	case ecosystems.PyPi:
		return entities.Ecosystem_ECOSYSTEM_PYPI
	default:
		return entities.Ecosystem_ECOSYSTEM_UNKNOWN
	}
}

// emitLatencyMetrics calculates and emits latency metrics from push events
func emitLatencyMetrics(pushedAt, ingestedAt *timestamppb.Timestamp, statter stats.Client, tags stats.Tags) {
	if pushedAt == nil {
		return
	}

	// Time since the push event to now
	statter.DistributionMs(
		"manifest.etl.job.dependabot_snapshot.latency_to_publishing_request",
		tags,
		time.Since(pushedAt.AsTime()),
	)

	// Time between the push event and when it was ingested
	if ingestedAt != nil {
		statter.DistributionMs(
			"manifest.etl.job.dependabot_snapshot.latency_to_ingest",
			tags,
			ingestedAt.AsTime().Sub(pushedAt.AsTime()),
		)
	}
}

func recordDependabotEvent(
	ctx context.Context,
	ffClient features.Client,
	dependabotEventSvc interfaces.DependabotEventService,
	logger log.Logger,
	statter stats.Client,
	repoID uint64,
	owner Owner,
	eventType interfaces.EventType,
	ref string,
	sha string,
	pushID *uint64,
	graphChanges map[GraphChange]struct{},
) (uint64, error) {
	enabled, err := isFeatureEnabled(ctx, ffClient, RepositoryAlertingFeatureFlag, repoID, owner)
	if err != nil {
		return 0, fmt.Errorf("failed to check repository alerting feature flag: %w", err)
	}
	if !enabled {
		logger.Info("recordDependabotEvent: skipped, feature flag disabled")
		statter.Counter("record_dependabot_event.skipped", stats.Tags{"reason": "feature_flag_disabled"}, 1)
		return 0, nil
	}

	entries := graphChangesToRequestedSnapshots(graphChanges)
	return dependabotEventSvc.RecordDependabotEvent(ctx, repoID, eventType, ref, sha, pushID, entries)
}

// dependabotEventProcessedMsg captures the event-specific data needed
// to publish a fully-populated DependabotEventProcessed Hydro message.
type dependabotEventProcessedMsg struct {
	RepoID    uint64
	Owner     Owner
	EventID   uint64
	EventType hydroproto.DependabotEventProcessed_EventType
	Ref       string
	SHA       string
	PushID    *uint64
	RequestID string
}

// publishDependabotEventFallback checks the alerting feature flag and, if
// enabled, publishes a DependabotEventProcessed Hydro message without an
// event_id.
//
// This signals to consumers that DS-API processed the trigger but did not
// record an event, allowing them to fall back to legacy manifest detection.
// The ref and sha are included when available (e.g. for push events) so
// consumers can correlate the fallback with the originating commit.
func publishDependabotEventFallback(
	ctx context.Context,
	publisher hydro.Publisher,
	ffClient features.Client,
	logger log.Logger,
	statter stats.Client,
	repoID uint64,
	owner Owner,
	eventType hydroproto.DependabotEventProcessed_EventType,
	requestID string,
	ref string,
	sha string,
) error {
	enabled, err := isFeatureEnabled(ctx, ffClient, RepositoryAlertingFeatureFlag, repoID, owner)
	if err != nil {
		statter.Counter("dependabot_event_processed.error", stats.Tags{"reason": "feature_flag_check"}, 1)
		return fmt.Errorf("failed to check feature flag: %w", err)
	}
	if !enabled {
		logger.Info("publishDependabotEventFallback: skipped, feature flag disabled")
		statter.Counter("dependabot_event_processed.skipped", stats.Tags{"reason": "feature_flag_disabled"}, 1)
		return nil
	}

	hydroMsg := &hydroproto.DependabotEventProcessed{
		RequestId:    requestID,
		RepositoryId: int64(repoID),
		EventType:    eventType,
		Ref:          ref,
		Sha:          sha,
	}

	if err := publisher.Publish(ctx, hydroMsg); err != nil {
		statter.Counter("dependabot_event_processed.error", stats.Tags{"reason": "publish_failed"}, 1)
		return fmt.Errorf("failed to publish DependabotEventProcessed: %w", err)
	}

	statter.Counter("dependabot_event_processed.success", stats.Tags{}, 1)
	return nil
}

// publishDependabotEventProcessed checks the alerting feature flag and, if
// enabled, publishes a fully-populated DependabotEventProcessed Hydro message
// for a recorded event.
func publishDependabotEventProcessed(
	ctx context.Context,
	publisher hydro.Publisher,
	ffClient features.Client,
	logger log.Logger,
	statter stats.Client,
	msg dependabotEventProcessedMsg,
) error {
	enabled, err := isFeatureEnabled(ctx, ffClient, RepositoryAlertingFeatureFlag, msg.RepoID, msg.Owner)
	if err != nil {
		statter.Counter("dependabot_event_processed.error", stats.Tags{"reason": "feature_flag_check"}, 1)
		return fmt.Errorf("failed to check feature flag: %w", err)
	}
	if !enabled {
		logger.Info("publishDependabotEventProcessed: skipped, feature flag disabled")
		statter.Counter("dependabot_event_processed.skipped", stats.Tags{"reason": "feature_flag_disabled"}, 1)
		return nil
	}

	hydroMsg := &hydroproto.DependabotEventProcessed{
		RequestId:    msg.RequestID,
		RepositoryId: int64(msg.RepoID),
		EventId:      int64(msg.EventID),
		EventType:    msg.EventType,
		Ref:          msg.Ref,
		Sha:          msg.SHA,
		ProcessedAt:  timestamppb.Now(),
	}
	if msg.PushID != nil && *msg.PushID != 0 {
		hydroMsg.PushId = int64(*msg.PushID)
	}

	if err := publisher.Publish(ctx, hydroMsg); err != nil {
		statter.Counter("dependabot_event_processed.error", stats.Tags{"reason": "publish_failed"}, 1)
		return fmt.Errorf("failed to publish DependabotEventProcessed: %w", err)
	}

	statter.Counter("dependabot_event_processed.success", stats.Tags{}, 1)
	return nil
}

func graphChangesToRequestedSnapshots(graphChanges map[GraphChange]struct{}) []interfaces.DependabotRequestedSnapshot {
	entries := make([]interfaces.DependabotRequestedSnapshot, 0, len(graphChanges))
	deadline := time.Now().Add(defaultDependabotSnapshotDeadlinePeriod)
	for gc := range graphChanges {
		entries = append(entries, interfaces.DependabotRequestedSnapshot{
			Ecosystem:    gc.Ecosystem.String(),
			ManifestPath: gc.Path,
			Deadline:     deadline,
		})
	}
	return entries
}
