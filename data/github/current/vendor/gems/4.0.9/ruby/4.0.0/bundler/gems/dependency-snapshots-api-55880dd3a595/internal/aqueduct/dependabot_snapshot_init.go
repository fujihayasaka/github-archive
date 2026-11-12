package aqueduct

import (
	"context"
	"strconv"

	hydroproto "github.com/github/dependency-snapshots-api/hydro/schemas/dependency_graph/v0"
	"github.com/github/dependency-snapshots-api/internal/aqueduct/manifests"
	"github.com/github/dependency-snapshots-api/internal/config"
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
	"github.com/twitchtv/twirp"
)

const (
	initJobMetricPrefix = "aqueduct.handler.dependabot_snapshot_init."
)

// HandleDependabotSnapshotInitJob processes a DependabotSnapshotInitJob message.
// This handler scans a repository for "Parse Once" ecosystem manifests that need
// to be dispatched to Dependabot for parsing.
//
// The handler:
// - Resolves the HEAD commit OID for the default branch
// - Enumerates all files at HEAD to identify manifests
// - Groups manifests by ecosystem and directory
// - Logs the detected graph changes (publishing not yet implemented)
//
// This is used for initial repository scans (e.g., on repository creation or
// enrollment) as opposed to incremental push-based processing.
func HandleDependabotSnapshotInitJob(
	ctx context.Context,
	cfg *config.Config,
	logger log.Logger,
	statter stats.Client,
	tracer *trace.Tracer,
	gitClient gitaccess.Client,
	publisher hydro.Publisher,
	ffClient features.Client,
	dependabotEventSvc interfaces.DependabotEventService,
	job *jobsproto.DependabotSnapshotInitJob,
) error {
	repoID := uint64(job.GetRepository().GetId())
	owner := extractOwnerFromInit(job.GetOwner())
	triggeredBy := job.GetTriggeredBy()

	logFields := []kvp.Field{
		semconv.RequestID(job.GetRequestId()),
		semconv.MessagingMessageID(job.GetEventId()),
		semconv.RepoID(repoID),
		semconv.GitRef(job.GetRef()),
		semconv.IsDefaultBranch(job.GetIsDefaultBranch()),
		semconv.JobTriggeredBy(triggeredBy.String()),
		tenant.GetTenantField(ctx),
		tenant.GetTenantIDField(ctx),
	}
	logger = logger.WithFields(logFields...)

	tags := stats.Tags{
		"triggered_by": triggeredBy.String(),
		"init_push":    strconv.FormatBool(true), // Always true for this handler
	}

	// skip for invalid repos
	if repoID == 0 {
		logger.Info("DependabotSnapshotInitJob skipped: invalid repository")
		statter.Counter(initJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "invalid_repo"}), 1)
		return nil
	}

	// initially only running for default branch pushes
	if !job.IsDefaultBranch {
		logger.Info("DependabotSnapshotInitJob skipped: triggered by non-default branch push")
		statter.Counter(initJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "non_default_branch"}), 1)
		return nil
	}

	jobData := extractInitJobData(job)

	// Get the default branch's HEAD commit OID
	head, err := gitClient.ResolveRef(ctx, repoID, "HEAD")
	if err != nil {
		// If the problem is a 404 from Spokes, that means the repository is empty so there's nothing to do.
		var twirpErr twirp.Error
		if errors.As(err, &twirpErr) && twirpErr.Code() == twirp.NotFound {
			logger.WithError(err).Info("DependabotSnapshotInitJob skipped: repository is empty, nothing to do")
			statter.Counter(initJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "empty_repo"}), 1)
			return nil
		}

		logger.WithError(err).Error("DependabotSnapshotInitJob failed to obtain HEAD commit for repo")
		statter.Counter(initJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "resolve_head"}), 1)
		return errors.Wrap(err, "failed to obtain HEAD commit for repo")
	}

	ecos, err := enabledEcosystems(ctx, ffClient, repoID, jobData.Owner)
	if err != nil {
		logger.WithError(err).Error("DependabotSnapshotInitJob failed to determine feature flagged ecosystems")
		statter.Counter(initJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "feature_flag_check"}), 1)
		return errors.Wrap(err, "failed to determine feature flagged ecosystems")
	}

	if len(ecos) == 0 {
		logger.Info("DependabotSnapshotInitJob skipped: no ecosystems enabled for repo")
		statter.Counter(initJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "feature_flag_disabled"}), 1)

		// Notify the monolith to hand off processing to legacy manifest detection
		if err := publishDependabotEventFallback(ctx, publisher, ffClient, logger, statter, repoID, owner, hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT, jobData.RequestID, job.GetRef(), head.GetId()); err != nil {
			return errors.Wrap(err, "failed to publish DependabotEventProcessed")
		}

		return nil
	}

	var groupedManifests manifests.RelatedManifests

	// enumerate & classify content at the latest HEAD of default branch commit
	enumerator := manifests.NewRepositoryEnumerator(cfg, tracer, statter, gitClient)
	groupedManifests, err = enumerator.Process(ctx, repoID, head.GetId())
	if err != nil {
		logger.WithError(err).Error(
			"DependabotSnapshotInitJob failed to enumerate and classify repository content from init push",
			kvp.String("commitOID", head.GetId()))
		statter.Counter(initJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "enumerator"}), 1)
		return errors.Wrap(err, "failed to enumerate and classify repository content from init push")
	}

	// Collect graph changes from manifests
	graphChanges := collectGraphChanges(groupedManifests, ecos)
	if len(graphChanges) == 0 {
		logger.Info("DependabotSnapshotInitJob skipped: no relevant manifest changes detected")
		statter.Counter(initJobMetricPrefix+"skipped", tags.Merge(stats.Tags{"reason": "no_manifest_changes"}), 1)

		// Notify the monolith to hand off processing to legacy manifest detection
		if err := publishDependabotEventFallback(ctx, publisher, ffClient, logger, statter, repoID, owner, hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT, jobData.RequestID, job.GetRef(), head.GetId()); err != nil {
			return errors.Wrap(err, "failed to publish DependabotEventProcessed")
		}

		return nil
	}

	// Record the event and snapshots we are going to request
	eventID, err := recordDependabotEvent(ctx, ffClient, dependabotEventSvc, logger, statter, repoID, owner, interfaces.EventTypeInit, job.GetRef(), head.GetId(), nil, graphChanges)
	if err != nil {
		statter.Counter(initJobMetricPrefix+"error", tags.Merge(stats.Tags{"reason": "record_event"}), 1)
		return errors.Wrap(err, "failed to record dependabot event")
	}

	// Build and publish the UpdateGraphEvent
	graphPayload := buildPayload(jobData, graphChanges, eventID)
	if err := publishGraphChanges(ctx, publisher, graphPayload, logger, statter, tags, initJobMetricPrefix); err != nil {
		return errors.Wrap(err, "failed to publish graph changes")
	}

	// Notify the monolith that processing is complete
	if err := publishDependabotEventProcessed(ctx, publisher, ffClient, logger, statter, dependabotEventProcessedMsg{
		RepoID:    repoID,
		Owner:     owner,
		EventID:   eventID,
		EventType: hydroproto.DependabotEventProcessed_EVENT_TYPE_INIT,
		Ref:       job.GetRef(),
		SHA:       head.GetId(),
		RequestID: jobData.RequestID,
	}); err != nil {
		return errors.Wrap(err, "failed to publish DependabotEventProcessed")
	}

	// Emit latency metrics
	emitLatencyMetrics(jobData.PushedAt, jobData.IngestedAt, statter, tags)

	return nil
}

func extractRepositoryFromInit(repo *jobsproto.DependabotSnapshotInitJob_Repository) Repository {
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

func extractOwnerFromInit(user *jobsproto.DependabotSnapshotInitJob_User) Owner {
	var ownerType OwnerType
	switch user.GetType() {
	case jobsproto.DependabotSnapshotInitJob_User_TYPE_USER:
		ownerType = OwnerTypeUser
	case jobsproto.DependabotSnapshotInitJob_User_TYPE_ORGANIZATION:
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

func extractInitJobData(job *jobsproto.DependabotSnapshotInitJob) snapshotJobData {
	return snapshotJobData{
		RequestID:       job.GetRequestId(),
		EventID:         job.GetEventId(),
		Repository:      extractRepositoryFromInit(job.GetRepository()),
		Owner:           extractOwnerFromInit(job.GetOwner()),
		Ref:             job.GetRef(),
		IsDefaultBranch: job.GetIsDefaultBranch(),
		TriggeredBy:     job.GetTriggeredBy().String(),
		PushedAt:        job.GetPushedAt(),
		IngestedAt:      job.GetIngestedAt(),
	}
}
