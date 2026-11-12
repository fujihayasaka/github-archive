package scheduler

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"math"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	agentconfigstore "github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	schedulercosmos "github.com/github/sweagentd/internal/scheduler/store/cosmos"
)

const (
	defaultTickInterval       = 30 * time.Second
	defaultStaleLockInterval  = 1 * time.Minute
	defaultStaleLockThreshold = 3 * time.Minute

	triggerJobErrorReasonExecute     = "execute_error"
	triggerJobErrorReasonLockAcquire = "lock_acquire_error"
)

type triggerJobError struct {
	reason string
	err    error
}

func (e *triggerJobError) Error() string {
	return e.err.Error()
}

func (e *triggerJobError) Unwrap() error {
	return e.err
}

func intervalTriggerJobError(reason string, err error) error {
	if err == nil {
		return nil
	}
	return &triggerJobError{reason: reason, err: err}
}

func intervalTriggerJobErrorReason(err error) string {
	var taggedErr *triggerJobError
	if errors.As(err, &taggedErr) && taggedErr.reason != "" {
		return taggedErr.reason
	}
	return triggerJobErrorReasonExecute
}

// TriggerStore defines the store operations the scheduler needs.
type TriggerStore interface {
	FindDueTriggers(ctx context.Context, now time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error)
	FindStaleLocks(ctx context.Context, threshold time.Time, limit int) ([]*schedulerstore.IntervalTriggerRecord, error)
	PatchTrigger(ctx context.Context, scopeID int64, id string, patch schedulerstore.IntervalTriggerPatch) (*azcore.ETag, error)
	Get(ctx context.Context, scopeID int64, id string) (*schedulerstore.IntervalTriggerRecord, error)
}

// TriggerExecutor defines how the scheduler executes a trigger.
type TriggerExecutor interface {
	Execute(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) error
}

// EnvRouter gates fire-time processing by environment so each stamp only fires
// triggers it owns. Optional — a nil router behaves as "process everything".
type EnvRouter interface {
	ShouldProcess(ctx context.Context, actorID, repoID, ownerID int64) bool
}

// Scheduler periodically queries for due interval triggers and creates agent jobs.
type Scheduler struct {
	triggerStore TriggerStore
	executor     TriggerExecutor
	hook         SchedulingHook
	envRouter    EnvRouter
	obsv         observability.Exporters
	workerID     string
	tickInterval time.Duration
	staleLockInt time.Duration
	staleLockThr time.Duration
}

// New creates a new Scheduler.
func New(
	triggerStore TriggerStore,
	executor TriggerExecutor,
	hook SchedulingHook,
	envRouter EnvRouter,
	obsv observability.Exporters,
	workerID string,
	tickInterval time.Duration,
	staleLockInt time.Duration,
	staleLockThr time.Duration,
) *Scheduler {
	if tickInterval <= 0 {
		tickInterval = defaultTickInterval
	}
	if staleLockInt <= 0 {
		staleLockInt = defaultStaleLockInterval
	}
	if staleLockThr <= 0 {
		staleLockThr = defaultStaleLockThreshold
	}

	return &Scheduler{
		triggerStore: triggerStore,
		executor:     executor,
		hook:         hook,
		envRouter:    envRouter,
		obsv:         obsv,
		workerID:     workerID,
		tickInterval: tickInterval,
		staleLockInt: staleLockInt,
		staleLockThr: staleLockThr,
	}
}

// Run starts the scheduler loop. It blocks until the context is cancelled.
func (s *Scheduler) Run(ctx context.Context) error {
	// Initialize requestctx data on the base context so that TelemetryTags,
	// LoggerWithTelemetry, and any AddRepo/AddUser calls work without panic.
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})

	ticker := time.NewTicker(s.tickInterval)
	defer ticker.Stop()

	go s.runStaleLockRecovery(ctx)

	s.obsv.LoggerWithTelemetry(ctx).Info("scheduler started",
		kvp.String("worker_id", s.workerID),
		kvp.Duration("tick_interval", s.tickInterval),
	)

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
			s.processTick(ctx)
		}
	}
}

func (s *Scheduler) processTick(ctx context.Context) {
	s.obsv.Increment(ctx, "scheduler.tick", stats.Tags{})
	startTime := time.Now()
	defer func() {
		s.obsv.DistributionMs(ctx, "scheduler.tick.duration_ms", stats.Tags{}, time.Since(startTime))
	}()

	batchSize := s.hook.GetBatchSize(ctx)
	s.obsv.Statter.Distribution("scheduler.tick.batch_size", s.obsv.TelemetryTags(ctx), float64(batchSize))

	tickStart := time.Now()
	triggers, err := s.triggerStore.FindDueTriggers(ctx, tickStart, batchSize)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to find due triggers")
		s.obsv.Increment(ctx, "scheduler.tick.error", stats.Tags{})
		return
	}

	triggerTags := stats.Tags{"trigger_type": "interval"}
	s.obsv.Statter.Distribution("scheduler.triggers_found", s.obsv.TelemetryTags(ctx), float64(len(triggers)))
	s.obsv.Statter.Distribution("scheduler.tick.batch_used", s.obsv.TelemetryTags(ctx), float64(len(triggers)))

	// A full batch means the scheduler is capacity-limited this tick; due-lag
	// can grow when this stays saturated. Alert on the rate of saturated ticks.
	if batchSize > 0 && len(triggers) == batchSize {
		s.obsv.Increment(ctx, "scheduler.tick.batch_saturated", triggerTags)
	}

	lagBaseTags := s.obsv.TelemetryTags(ctx).Merge(triggerTags)
	for _, trigger := range triggers {
		lagSeconds := max(tickStart.Unix()-trigger.NextRunAt, 0)
		s.obsv.Statter.Distribution(
			"scheduler.due_lag_seconds",
			lagBaseTags.Merge(stats.Tags{"interval_type": trigger.IntervalType}),
			float64(lagSeconds),
		)
	}

	if len(triggers) > 0 {
		s.obsv.LoggerWithTelemetry(ctx).Info("scheduler: processing due triggers",
			kvp.Int("count", len(triggers)),
		)
	}

	var processed, skipped int
	for _, trigger := range triggers {
		if !s.hook.ShouldProcess(ctx, trigger.ID, trigger.ScopeID) {
			s.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "hook"}))
			skipped++
			continue
		}

		// Cross-stamp gate: only the stamp routed for this actor/repo/owner fires the trigger.
		if s.envRouter != nil && !s.envRouter.ShouldProcess(ctx, trigger.ActorID, trigger.RepoID, trigger.RepoOwnerID) {
			s.obsv.Increment(ctx, "triggers.skipped", triggerTags.Merge(stats.Tags{"reason": "env_routing"}))
			skipped++
			continue
		}

		triggerCtx := s.enrichContext(ctx, trigger)
		intervalTags := triggerTags.Merge(stats.Tags{"interval_type": trigger.IntervalType})

		s.obsv.Increment(triggerCtx, "triggers.received", intervalTags)

		acquired, lockETag, err := s.tryAcquireLock(triggerCtx, trigger)
		if err != nil {
			s.obsv.LoggerWithTelemetry(triggerCtx).WithError(err).Error("failed to acquire lock",
				kvp.String("trigger_id", trigger.ID),
			)
			s.obsv.Increment(triggerCtx, "triggers.job_error", intervalTags.Merge(stats.Tags{"reason": triggerJobErrorReasonLockAcquire}))
			continue
		}
		if !acquired {
			s.obsv.Increment(triggerCtx, "triggers.skipped", intervalTags.Merge(stats.Tags{"reason": "lock_conflict"}))
			skipped++
			continue
		}
		s.obsv.Increment(triggerCtx, "scheduler.lock_acquired", stats.Tags{})

		err = s.executor.Execute(triggerCtx, trigger)
		if err != nil {
			if errors.Is(err, agentconfigstore.ErrAgentNotFound) {
				// Agent was deleted but trigger record still exists. Log a warning
				// and advance the schedule so we don't retry every tick.
				s.obsv.LoggerWithTelemetry(triggerCtx).Warn("agent not found for trigger, skipping",
					kvp.String("trigger_id", trigger.ID),
					kvp.String("agent_id", trigger.AgentID),
				)
				s.obsv.Increment(triggerCtx, "triggers.skipped", intervalTags.Merge(stats.Tags{"reason": "agent_not_found"}))
				s.releaseLockAndAdvanceSchedule(triggerCtx, trigger, lockETag)
				skipped++
				continue
			}

			if errors.Is(err, ErrAutomationsDisabled) {
				// Skip-and-advance: Checker already emitted the metric/log.
				s.releaseLockAndAdvanceSchedule(triggerCtx, trigger, lockETag)
				skipped++
				continue
			}

			s.obsv.LoggerWithTelemetry(triggerCtx).WithError(err).Error("failed to execute trigger",
				kvp.String("trigger_id", trigger.ID),
			)
			s.obsv.Increment(triggerCtx, "triggers.job_error", intervalTags.Merge(stats.Tags{"reason": intervalTriggerJobErrorReason(err)}))
			s.releaseLockOnly(triggerCtx, trigger, lockETag)
			continue
		}

		s.obsv.Increment(triggerCtx, "triggers.job_queued", intervalTags)
		s.releaseLockWithSchedule(triggerCtx, trigger, lockETag)
		processed++
	}

	if len(triggers) > 0 {
		s.obsv.Increment(ctx, "triggers.handled", triggerTags)
		s.obsv.LoggerWithTelemetry(ctx).Info("scheduler: tick complete",
			kvp.Int("due", len(triggers)),
			kvp.Int("processed", processed),
			kvp.Int("skipped", skipped),
		)
	}
}

func (s *Scheduler) tryAcquireLock(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) (bool, *azcore.ETag, error) {
	now := time.Now().Unix()
	patch := schedulerstore.IntervalTriggerPatch{
		LockedBy: &s.workerID,
		LockedAt: &now,
		ETag:     trigger.ETag,
	}

	newETag, err := s.triggerStore.PatchTrigger(ctx, trigger.ScopeID, trigger.ID, patch)
	if err != nil {
		if errors.Is(err, schedulercosmos.ErrConflict) {
			return false, nil, nil
		}
		return false, nil, err
	}
	return true, newETag, nil
}

func (s *Scheduler) releaseLockWithSchedule(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord, lockETag *azcore.ETag) {
	nextRunAt := s.calculateNextRunAt(trigger)
	nextRunAtUnix := nextRunAt.Unix()
	lastRunAtUnix := time.Now().Unix()
	empty := ""

	patch := schedulerstore.IntervalTriggerPatch{
		LockedBy:  &empty,
		LockedAt:  new(int64), // zero value
		NextRunAt: &nextRunAtUnix,
		LastRunAt: &lastRunAtUnix,
		ETag:      lockETag,
	}

	_, err := s.triggerStore.PatchTrigger(ctx, trigger.ScopeID, trigger.ID, patch)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to update schedule after job creation",
			kvp.String("trigger_id", trigger.ID),
		)
		return
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("scheduler: trigger executed, next run scheduled",
		kvp.String("trigger_id", trigger.ID),
		kvp.String("interval_type", trigger.IntervalType),
		kvp.Int64("next_run_at", nextRunAtUnix),
	)
}

// releaseLockAndAdvanceSchedule releases the lock and advances NextRunAt without
// updating LastRunAt. Use this when a trigger is skipped (e.g. agent not found)
// to prevent it from firing again on the next tick.
func (s *Scheduler) releaseLockAndAdvanceSchedule(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord, lockETag *azcore.ETag) {
	nextRunAt := s.calculateNextRunAt(trigger)
	nextRunAtUnix := nextRunAt.Unix()
	empty := ""

	patch := schedulerstore.IntervalTriggerPatch{
		LockedBy:  &empty,
		LockedAt:  new(int64), // zero value
		NextRunAt: &nextRunAtUnix,
		ETag:      lockETag,
	}

	_, err := s.triggerStore.PatchTrigger(ctx, trigger.ScopeID, trigger.ID, patch)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to advance schedule",
			kvp.String("trigger_id", trigger.ID),
		)
		return
	}

	s.obsv.LoggerWithTelemetry(ctx).Info("scheduler: trigger skipped, next run scheduled",
		kvp.String("trigger_id", trigger.ID),
		kvp.String("interval_type", trigger.IntervalType),
		kvp.Int64("next_run_at", nextRunAtUnix),
	)
}

func (s *Scheduler) releaseLockOnly(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord, lockETag *azcore.ETag) {
	empty := ""
	patch := schedulerstore.IntervalTriggerPatch{
		LockedBy: &empty,
		LockedAt: new(int64), // zero value
		ETag:     lockETag,
	}

	_, err := s.triggerStore.PatchTrigger(ctx, trigger.ScopeID, trigger.ID, patch)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to release lock (best effort)",
			kvp.String("trigger_id", trigger.ID),
		)
	}
}

// calculateNextRunAt computes the next execution time for a trigger using the hook's scatter duration.
func (s *Scheduler) calculateNextRunAt(trigger *schedulerstore.IntervalTriggerRecord) time.Time {
	return computeNextRunAt(time.Now().UTC(), trigger.Schedule(), trigger.ScatterOffset, s.hook, false)
}

// CalculateInitialNextRunAt computes the first execution time for a new trigger.
// If the current window's scatter time is still in the future, uses it; otherwise schedules for next window.
func CalculateInitialNextRunAt(intervalType string, scatterOffset float64, hook SchedulingHook) time.Time {
	return CalculateInitialNextRunAtForSchedule(schedulerstore.Schedule{IntervalType: intervalType}, scatterOffset, hook)
}

// CalculateInitialNextRunAtForSchedule is the anchor-aware variant of CalculateInitialNextRunAt.
func CalculateInitialNextRunAtForSchedule(schedule schedulerstore.Schedule, scatterOffset float64, hook SchedulingHook) time.Time {
	return computeNextRunAt(time.Now().UTC(), schedule, scatterOffset, hook, true)
}

// computeNextRunAt is the shared schedule math. Pure function: takes now as a parameter
// so tests can pin a clock.
// allowCurrentWindow=false: always advance to the next window (post-execution recompute).
// allowCurrentWindow=true:  use the current window's candidate if still in the future
func computeNextRunAt(nowUTC time.Time, schedule schedulerstore.Schedule, scatterOffset float64, hook SchedulingHook, allowCurrentWindow bool) time.Time {
	// Defensive clamp: catches pre-clamp persisted offsets and manual Cosmos edits.
	scatterOffset = clampScatterOffset(scatterOffset)
	jitterWindow := hook.GetScatterDuration(schedule)
	scatterDur := time.Duration(float64(jitterWindow) * scatterOffset)

	currentAnchor := currentWindowAnchor(nowUTC, schedule)

	if allowCurrentWindow {
		candidate := currentAnchor.Add(scatterDur)
		if candidate.After(nowUTC) {
			return candidate
		}
	}

	return nextWindowAnchor(currentAnchor, schedule).Add(scatterDur)
}

// clampScatterOffset coerces a scatter offset into the half-open [0, 1) range.
func clampScatterOffset(v float64) float64 {
	if math.IsNaN(v) || v < 0 {
		return 0
	}
	if v >= 1.0 {
		return math.Nextafter(1.0, 0)
	}
	return v
}

// currentWindowAnchor returns the start instant of the window that contains nowUTC
// for the given schedule.
func currentWindowAnchor(nowUTC time.Time, schedule schedulerstore.Schedule) time.Time {
	switch schedule.IntervalType {
	case schedulerstore.IntervalTypeHourly:
		return nowUTC.Truncate(time.Hour)

	case schedulerstore.IntervalTypeWeekly:
		anchorDay := time.Monday
		if d, ok := validDayOfWeek(schedule.AnchorDayOfWeek); ok {
			anchorDay = time.Weekday(d)
		}
		anchorHour := 0
		if h, ok := validHour(schedule.AnchorHourUTC); ok {
			anchorHour = h
		}
		daysSinceAnchor := (int(nowUTC.Weekday()) - int(anchorDay) + 7) % 7
		candidate := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day()-daysSinceAnchor, anchorHour, 0, 0, 0, time.UTC)
		if candidate.After(nowUTC) {
			candidate = candidate.AddDate(0, 0, -7)
		}
		return candidate

	default: // daily
		anchorHour := 0
		if h, ok := validHour(schedule.AnchorHourUTC); ok {
			anchorHour = h
		}
		candidate := time.Date(nowUTC.Year(), nowUTC.Month(), nowUTC.Day(), anchorHour, 0, 0, 0, time.UTC)
		if candidate.After(nowUTC) {
			candidate = candidate.AddDate(0, 0, -1)
		}
		return candidate
	}
}

// validHour returns (h, true) when ptr is a valid UTC hour in [0, 23].
// Out-of-range values fall back to the legacy unanchored default rather than
// silently rolling through time.Date's normalisation.
func validHour(ptr *int) (int, bool) {
	if ptr == nil || *ptr < 0 || *ptr > 23 {
		return 0, false
	}
	return *ptr, true
}

// validDayOfWeek returns (d, true) when ptr is a valid weekday in [0, 6].
// Out-of-range values fall back to the legacy unanchored default.
func validDayOfWeek(ptr *int) (int, bool) {
	if ptr == nil || *ptr < 0 || *ptr > 6 {
		return 0, false
	}
	return *ptr, true
}

// nextWindowAnchor returns the next anchor instant after the given current anchor.
func nextWindowAnchor(currentAnchor time.Time, schedule schedulerstore.Schedule) time.Time {
	switch schedule.IntervalType {
	case schedulerstore.IntervalTypeHourly:
		return currentAnchor.Add(time.Hour)
	case schedulerstore.IntervalTypeWeekly:
		return currentAnchor.AddDate(0, 0, 7)
	default: // daily
		return currentAnchor.AddDate(0, 0, 1)
	}
}

// GenerateScatterOffset generates a random scatter offset in [0, 1).
// Falls back to 0.5 if crypto/rand fails.
func GenerateScatterOffset() float64 {
	var buf [8]byte
	n, err := rand.Read(buf[:])
	if err != nil || n != len(buf) {
		return 0.5
	}
	return clampScatterOffset(float64(binary.BigEndian.Uint64(buf[:])) / float64(math.MaxUint64))
}

func (s *Scheduler) runStaleLockRecovery(ctx context.Context) {
	ticker := time.NewTicker(s.staleLockInt)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			s.recoverStaleLocks(ctx)
		}
	}
}

func (s *Scheduler) recoverStaleLocks(ctx context.Context) {
	threshold := time.Now().Add(-s.staleLockThr)

	staleTriggers, err := s.triggerStore.FindStaleLocks(ctx, threshold, 100)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to find stale locks")
		return
	}

	for _, trigger := range staleTriggers {
		empty := ""
		patch := schedulerstore.IntervalTriggerPatch{
			LockedBy: &empty,
			LockedAt: new(int64),
			ETag:     trigger.ETag,
		}

		_, err := s.triggerStore.PatchTrigger(ctx, trigger.ScopeID, trigger.ID, patch)
		if err != nil {
			if !errors.Is(err, schedulercosmos.ErrConflict) {
				s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to recover stale lock",
					kvp.String("trigger_id", trigger.ID),
					kvp.String("locked_by", trigger.LockedBy),
				)
			}
			continue
		}
		s.obsv.Increment(ctx, "scheduler.stale_locks_recovered", stats.Tags{})
		s.obsv.LoggerWithTelemetry(ctx).Info("recovered stale lock",
			kvp.String("trigger_id", trigger.ID),
			kvp.String("locked_by", trigger.LockedBy),
		)
	}
}

// enrichContext adds repo metadata, agent identity, and a request ID to the context so
// that TelemetryTags and LoggerWithTelemetry automatically include them.
func (s *Scheduler) enrichContext(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) context.Context {
	ctx = requestid.WithNewGitHubRequestID(ctx)
	ctx = requestctx.AddData(ctx, &requestctx.CtxData{})
	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      trigger.RepoID,
		OwnerID: trigger.RepoOwnerID,
	})
	_ = requestctx.AddCustomAgent(ctx, &requestctx.CtxCustomAgent{
		ID: trigger.AgentID,
	})
	return ctx
}
