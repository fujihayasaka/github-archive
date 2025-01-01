package scheduled

import (
	"context"
	"encoding/json"
	"fmt"
	"strconv"
	"time"

	"github.com/github/go-ctxutil"
	"github.com/github/go-kvp"
	"github.com/google/uuid"
	"github.com/pkg/errors"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/trace"

	"github.com/github/launch/clients/aqueduct"
	"github.com/github/launch/clients/ghtwirp"
	"github.com/github/launch/clients/github"
	"github.com/github/launch/db/stores/schedules"
	"github.com/github/launch/flow/flowevents"
	"github.com/github/launch/observability/ctxstash"
	"github.com/github/launch/observability/logger"
	"github.com/github/launch/observability/statter"
	"github.com/github/launch/observability/tracing"
	"github.com/github/launch/pkg/launchcache"
	"github.com/github/launch/pkg/processors/build"
	"github.com/github/launch/pkg/tiers"
	"github.com/github/launch/services/deploy/scheduled/config"
	"github.com/github/launch/services/deploy/workflowinvoker"
	"github.com/github/launch/types"
	"github.com/github/launch/utils/appcontext"
	"github.com/github/launch/utils/ghtenant"
	"github.com/github/launch/workerpool"
)

const (
	maximumQueueDepth     = 500
	queueDepthThreshold   = 250
	queueDepthCacheExpiry = 60 * time.Second

	tier1ScheduleDelayThreshold = 5 * time.Minute
	tier2ScheduleDelayThreshold = 15 * time.Minute
	tier3ScheduleDelayThreshold = 60 * time.Minute
)

type worker struct {
	ID                    string
	store                 schedules.Store
	log                   logger.Logger
	cfg                   config.ScheduledConfig
	isEnterprise          bool
	isMultiTenant         bool
	statter               statter.Statter
	metadata              appcontext.ApplicationMetadata
	githubTwirpClient     ghtwirp.Client
	isLab                 bool
	aqueductClient        aqueduct.Client
	aqueductQueue         string
	aqueductApp           string
	launchDependencyCache launchcache.LaunchDependencyCache
}

func newWorker(
	hostname string,
	store schedules.Store,
	logger logger.Logger,
	cfg config.ScheduledConfig,
	statter statter.Statter,
	metadata appcontext.ApplicationMetadata,
	ghTwirpClient ghtwirp.Client,
	aqueductClient aqueduct.Client,
	aqueductQueue string,
	aqueductApp string,
	isEnterprise bool,
	isLab bool,
	isMultiTenant bool,
	launchDependencyCache launchcache.LaunchDependencyCache,
) *worker {
	return &worker{
		ID:                    fmt.Sprintf("worker-%s", hostname),
		store:                 store,
		log:                   logger,
		cfg:                   cfg,
		statter:               statter,
		metadata:              metadata,
		githubTwirpClient:     ghTwirpClient,
		aqueductClient:        aqueductClient,
		aqueductQueue:         aqueductQueue,
		aqueductApp:           aqueductApp,
		isEnterprise:          isEnterprise,
		isLab:                 isLab,
		isMultiTenant:         isMultiTenant,
		launchDependencyCache: launchDependencyCache,
	}
}

func (w *worker) getTick() workerpool.JobFunc {
	return func(ctx context.Context) error {
		return w.tick(ctx)
	}
}

func (w *worker) tick(ctx context.Context) error {
	ctx, span := tracing.StartWithOpFuncName(ctx, "scheduled.worker.tick", trace.WithAttributes(
		attribute.String("gh.launch.worker.id", w.ID),
	))
	defer span.End()

	isDisabled := w.githubTwirpClient.IsFeatureEnabledGlobally(ctx, github.DisableScheduledWorkflowsFeatureFlag)
	if isDisabled {
		w.log.Debug(ctx, "scheduled workflows are disabled, skipping run")
		return nil
	}

	if w.isLab && w.githubTwirpClient.IsFeatureEnabledGlobally(ctx, github.DisableScheduledWorkflowsInLabFeatureFlag) {
		w.log.Debug(ctx, "scheduled workflows are disabled in lab, skipping run")
		return nil
	}

	tasksPerTick := w.getTasksPerTick(ctx)
	if tasksPerTick == 0 {
		w.log.Debug(ctx, "tasksPerTick is 0, not queueing scheduled builds")
		return nil
	}

	scheduled, err := w.store.FindAndLock(ctx, w.ID, tasksPerTick)

	if err != nil {
		return tracing.RecordError(span, err)
	}

	for _, schedule := range scheduled {
		w.run(ctx, schedule)
	}

	return nil
}

func (w *worker) run(ctx context.Context, schedule schedules.ScheduleRun) {
	_, span := tracing.StartWithOpFuncName(ctx, "scheduled.worker.run", trace.WithAttributes(
		attribute.String("gh.launch.commit_sha", string(schedule.CommitSHA)),
		attribute.String("gh.launch.schedule_id", strconv.FormatUint(schedule.ID, 10)),
	))
	defer span.End()

	var eventOriginTime time.Time
	var scheduleDelay time.Duration
	if schedule.NextRunAt != nil {
		scheduleDelay = time.Since(*schedule.NextRunAt)
		eventOriginTime = *schedule.NextRunAt
	}
	withinThreshold := isScheduleDelayWithinThreshold(schedule.Tier, scheduleDelay)

	// Create a new context unconnected to the lifespan of the parent context (which will
	// be cancelled when the tick returns), that will be passed through to invoker. Since
	// invoker runs its job asynchronously we need a longer-lived context

	ctx = ctxutil.DetachedCancel(ctx)

	ctx, err := appcontext.Initialize(ctx, w.metadata)
	if err != nil {
		w.log.Report(ctx, tracing.RecordError(span, err))
		return
	}

	ctx = ctxstash.WithFields(ctx,
		kvp.String("gh.launch.schedule_id", fmt.Sprintf("%v", schedule.ID)),
		kvp.String("gh.repo.global_id", schedule.RepositoryNodeID.String()),
		kvp.String("gh.actor.global_id", schedule.ActorNodeID.String()),
		kvp.String("gh.launch.schedule", schedule.Schedule),
		kvp.Int64("gh.launch.owner.id", schedule.OwnerID),
		kvp.String("gh.launch.workflow.file_path", schedule.WorkflowFilePath),
		kvp.String("gh.launch.workflow.identifier", schedule.WorkflowIdentifier),
		kvp.String("gh.launch.commit_sha", schedule.CommitSHA.String()),
		kvp.Int64("gh.launch.schedule_delay_ms", int64(scheduleDelay/time.Millisecond)),
	)

	_, repoDatabaseID, err := schedule.RepositoryNodeID.Decode()
	if err != nil {
		w.log.Report(ctx, errors.New("Failed to decode repository global ID"), kvp.Err(err))
	}

	// This will back-fill owner IDs for schedules that were created before we started to
	// persist them. This does not add any additional calls to the execution, if the
	// owner ID is 0 we'd have to make a call to gh.com anyway to fetch the correct one.
	if schedule.OwnerID == 0 {
		w.log.Log(ctx, "Schedule does not have an owner id, retrieve it.")
		ownerID, err := w.githubTwirpClient.GetRepositoryOwnerID(ctx, repoDatabaseID, true)
		if err != nil {
			w.log.Error(ctx, "Could not fetch owner id: could not find owner id by repo id", kvp.Err(err))
		} else {
			// Persist in the database for future executions
			if err := w.store.UpdateOwnerID(ctx, schedule.RepositoryNodeID, ownerID); err != nil {
				w.log.Error(ctx, "Could not update owner id")
			}
		}

		schedule.OwnerID = ownerID
	}

	w.log.Debug(ctx, "schedule queue attempt")

	isDisabled, err := w.githubTwirpClient.IsRepositoryActionsDisabled(ctx, schedule.RepositoryNodeID)
	if err != nil {
		w.log.Report(ctx, err)
	} else if isDisabled {
		w.log.Log(ctx, "Skipping scheduled execution and removing schedules, repo actions are disabled")
		err := w.store.RemoveSchedules(ctx, schedule.RepositoryNodeID)
		if err != nil {
			w.log.Report(ctx, errors.Wrap(err, "error removing workflow schedules"))
			return
		}

		return
	}

	eventPayload := createEventPayload(ctx, w.githubTwirpClient, w.log, repoDatabaseID, schedule)

	payloadJSON, err := json.Marshal(eventPayload)
	if err != nil {
		w.log.Report(ctx, tracing.RecordError(span, errors.Wrap(err, "failed to encode schedule payload")))
		return
	}

	// Generate a synthetic delivery ID for the scheduled build, that'll make the resulting
	// workflow build handling idempotent.
	scheduledDeliveryID := uuid.New().String()

	executingActor := workflowinvoker.NewActor(
		schedule.ActorNodeID,
		schedule.ActorLogin,
	)

	triggeringActor := executingActor

	var githubTenant ghtenant.GitHubTenant
	if w.isMultiTenant {
		if len(eventPayload.Enterprise) == 0 {
			w.log.Report(ctx, errors.New("expected github enterprise tenant data to be present in event payload"))
			return
		}

		// JSON Number types are always float64
		enterpriseID, ok := eventPayload.Enterprise["id"].(float64)
		if !ok {
			w.log.Report(ctx, errors.New("expected github enterprise id to be in event payload and be a number"))
			return
		}

		enterpriseSlug, ok := eventPayload.Enterprise["slug"].(string)
		if !ok {
			w.log.Report(ctx, errors.New("expected github enterprise slug to be in event payload and be a string"))
			return
		}

		githubTenant.ID = int64(enterpriseID)
		githubTenant.Slug = enterpriseSlug
	}

	invocation := workflowinvoker.NewInvocation(
		workflowinvoker.NewEvent(
			&scheduledDeliveryID,
			types.DefaultBranch,
			schedule.CommitSHA,
			types.CommitMessageZeroValue, // no need for commit message in scheduled runs
			flowevents.ScheduleEventName,
			"", // No action for schedule events
			payloadJSON,
			time.Now(),
			// EventOriginTime is the time the scheduled build was supposed to run. It might be in the past
			// due to limited resources.
			eventOriginTime,
			flowevents.ScheduleEvent{},
		),
		executingActor,
		triggeringActor,
		workflowinvoker.NewTarget(
			schedule.RepositoryNodeID,
			repoDatabaseID,
			workflowinvoker.WorkflowSelector{
				Path:      &schedule.WorkflowFilePath,
				EventName: flowevents.ScheduleEventName,
			},
			types.NilGlobalID,
			schedule.OwnerID,
			githubTenant,
		),
	)

	job := build.Job{
		Invocation: invocation,
	}

	payload, err := json.Marshal(job)
	if err != nil {
		w.log.Report(ctx, errors.Wrap(err, "Could not serialize invocation job"))

		// Exit here without scheduling the next run so that it will be retried later
		return
	}

	aqJob := aqueduct.Job{App: w.aqueductApp, Queue: w.aqueductQueue, Payload: payload}

	jobID, err := w.aqueductClient.Send(ctx, aqJob)
	if err != nil {
		w.log.Report(ctx, errors.Wrap(err, "Could not queue scheduled invocation"))
		tags := statter.Tags{
			"outcome":          "failed",
			"tier":             strconv.Itoa(int(schedule.Tier)),
			"within_threshold": strconv.FormatBool(withinThreshold),
		}
		w.statter.LegacyTiming(ctx, "scheduled.queued", tags, scheduleDelay)
		w.statter.Timing(ctx, "scheduled.queued_build", tags, scheduleDelay)
		// Exit here without scheduling the next run so that it will be retried later
		return
	}
	tags := statter.Tags{
		"outcome":          "success",
		"tier":             strconv.Itoa(int(schedule.Tier)),
		"within_threshold": strconv.FormatBool(withinThreshold),
	}
	w.statter.LegacyTiming(ctx, "scheduled.queued", tags, scheduleDelay)
	w.statter.Timing(ctx, "scheduled.queued_build", tags, scheduleDelay)
	w.log.Log(ctx, "scheduled build queued",
		kvp.String("gh.aqueduct.job.id", jobID),
		kvp.Bool("gh.launch.within_threshold", withinThreshold),
		kvp.Int64("gh.launch.schedule_run.tier", int64(schedule.Tier)))

	w.updateTierIfExpired(ctx, &schedule)

	err = w.store.ScheduleNextRun(ctx, schedule)
	if err == nil {
		w.log.Debug(ctx, "schedule next run written")
	} else {
		w.log.Report(ctx, err)
		return
	}
}

func (w *worker) updateTierIfExpired(ctx context.Context, schedule *schedules.ScheduleRun) {
	now := time.Now().UTC()
	if schedule.TierUpdatedAt != nil && schedule.TierUpdatedAt.After(now.Add(-w.cfg.TierCacheExpiration)) {
		return
	}

	var tier types.RepositoryTier
	if w.isEnterprise {
		tier = types.RepositoryTier1
	} else {
		var err error
		tier, err = tiers.FetchRepositoryTier(ctx, w.log, w.githubTwirpClient, schedule.RepositoryNodeID)
		if err != nil {
			// There was some issue getting the tier from dotcom. Not fatal, we just default to tier 3
			w.log.Report(ctx, err)
		}
	}

	schedule.Tier = tier
	schedule.TierUpdatedAt = &now
}

func (w *worker) getTasksPerTick(ctx context.Context) int {
	cache := w.launchDependencyCache.AqueductQueueDepthCacheFor(w.aqueductQueue)
	queueDepth, cacheHit, err := cache.Get(ctx)
	if err != nil {
		w.log.Error(ctx, "error getting queue depth from cache", kvp.Err(err))
	}
	if !cacheHit {
		queueDepth, err := w.aqueductClient.QueueDepth(ctx, w.aqueductApp, w.aqueductQueue)
		if err != nil {
			w.log.Error(ctx, "error getting queue depth, use the default configuration", kvp.Err(err))
			return w.cfg.TasksPerTick
		}

		if err := cache.Set(ctx, queueDepth, queueDepthCacheExpiry); err != nil {
			w.log.Report(ctx, errors.Wrap(err, "setting value in cache"))
		}
	}

	tasksPerTick := w.cfg.TasksPerTick
	if queueDepth > maximumQueueDepth {
		tasksPerTick = 0
	} else if queueDepth > queueDepthThreshold {
		tasksPerTick = tasksPerTick / 2
	}

	w.statter.Distribution(ctx, "scheduled.calculated_tasks_per_tick", nil, float64(tasksPerTick))
	return tasksPerTick
}

func isScheduleDelayWithinThreshold(tier types.RepositoryTier, delay time.Duration) bool {
	switch tier {
	case types.RepositoryTier1:
		return delay < tier1ScheduleDelayThreshold
	case types.RepositoryTier2:
		return delay < tier2ScheduleDelayThreshold
	case types.RepositoryTier3:
		return delay < tier3ScheduleDelayThreshold
	default:
		return false
	}
}
