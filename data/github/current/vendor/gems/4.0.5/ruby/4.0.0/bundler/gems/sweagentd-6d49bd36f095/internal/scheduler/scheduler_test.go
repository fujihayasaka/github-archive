package scheduler

import (
	"context"
	"sync"
	"testing"
	"time"

	stats "github.com/github/go-stats"
	agentconfigstore "github.com/github/sweagentd/internal/customagent/store"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	triggermemory "github.com/github/sweagentd/internal/scheduler/store/memory"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// mockExecutor records calls to Execute.
type mockExecutor struct {
	calls []string
	err   error
}

func (m *mockExecutor) Execute(_ context.Context, trigger *schedulerstore.IntervalTriggerRecord) error {
	m.calls = append(m.calls, trigger.ID)
	return m.err
}

func seedTrigger(t *testing.T, store *triggermemory.Store, scopeID int64, agentID string, nextRunAt int64) *schedulerstore.IntervalTriggerRecord {
	t.Helper()
	trigger, err := store.Upsert(context.Background(), &schedulerstore.IntervalTriggerRecord{
		ID:             uuid.NewString(),
		Scope:          schedulerstore.ScopeRepository,
		ScopeID:        scopeID,
		AgentID:        agentID,
		IntervalType:   schedulerstore.IntervalTypeDaily,
		ScatterOffset:  0.5,
		NextRunAt:      nextRunAt,
		ActorID:        200,
		ActorLogin:     "pusher",
		RepoID:         scopeID,
		RepoOwnerID:    100,
		RepoOwnerLogin: "my-org",
		RepoName:       "my-repo",
		TreeOID:        "abc123",
	})
	require.NoError(t, err)
	return trigger
}

func TestProcessTick_ProcessesDueTrigger(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{}
	obsv := observability.NewNoopExporters()

	agentID := uuid.NewString()
	trigger := seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	require.Len(t, executor.calls, 1)
	assert.Equal(t, trigger.ID, executor.calls[0])

	// Verify schedule was updated: NextRunAt should be in the future and lock cleared.
	triggers, err := triggerStore.ListByScopeID(context.Background(), 42)
	require.NoError(t, err)
	require.Len(t, triggers, 1)
	assert.Greater(t, triggers[0].NextRunAt, time.Now().Unix())
	assert.Empty(t, triggers[0].LockedBy)
	assert.Zero(t, triggers[0].LockedAt)
	assert.NotZero(t, triggers[0].LastRunAt)
}

func TestProcessTick_LockConflict(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{}
	obsv := observability.NewNoopExporters()

	agentID := uuid.NewString()
	trigger := seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	// Simulate another worker locking the trigger (changes ETag in store).
	lockTime := time.Now().Unix()
	_, err := triggerStore.PatchTrigger(context.Background(), trigger.ScopeID, trigger.ID, schedulerstore.IntervalTriggerPatch{
		LockedBy: strPtr("other-worker"),
		LockedAt: &lockTime,
	})
	require.NoError(t, err)

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	// processTick with stale ETag should gracefully skip.
	s.processTick(context.Background())
	assert.Empty(t, executor.calls)
}

func TestRecoverStaleLocks(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{}
	obsv := observability.NewNoopExporters()

	staleLockThreshold := 5 * time.Minute

	agentID := uuid.NewString()
	trigger := seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	// Lock the trigger with a timestamp older than the threshold.
	staleLockTime := time.Now().Add(-10 * time.Minute).Unix()
	_, err := triggerStore.PatchTrigger(context.Background(), trigger.ScopeID, trigger.ID, schedulerstore.IntervalTriggerPatch{
		LockedBy: strPtr("dead-worker"),
		LockedAt: &staleLockTime,
		ETag:     trigger.ETag,
	})
	require.NoError(t, err)

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, staleLockThreshold,
	)

	s.recoverStaleLocks(context.Background())

	// Lock should be cleared.
	triggers, err := triggerStore.ListByScopeID(context.Background(), 42)
	require.NoError(t, err)
	require.Len(t, triggers, 1)
	assert.Empty(t, triggers[0].LockedBy)
	assert.Zero(t, triggers[0].LockedAt)
}

func TestProcessTick_AgentNotFound_AdvancesSchedule(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{err: goerrors.Errorf("failed to get agent config: %w", agentconfigstore.ErrAgentNotFound)}
	obsv := observability.NewNoopExporters()

	agentID := uuid.NewString()
	seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	// Executor was called.
	require.Len(t, executor.calls, 1)

	// Schedule should have advanced (NextRunAt in the future) despite the error,
	// so the trigger doesn't fire again on the very next tick.
	triggers, err := triggerStore.ListByScopeID(context.Background(), 42)
	require.NoError(t, err)
	require.Len(t, triggers, 1)
	assert.Greater(t, triggers[0].NextRunAt, time.Now().Unix(), "NextRunAt should be advanced to the future")
	assert.Empty(t, triggers[0].LockedBy, "lock should be released")
	assert.Zero(t, triggers[0].LastRunAt, "LastRunAt should not be set for a skipped trigger")
}

// TestProcessTick_AutomationsDisabled_AdvancesSchedule verifies the automations-policy
// path: ErrAutomationsDisabled is treated as skip-and-advance.
func TestProcessTick_AutomationsDisabled_AdvancesSchedule(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{err: goerrors.Errorf("automations disabled: %w", ErrAutomationsDisabled)}
	obsv := observability.NewNoopExporters()

	agentID := uuid.NewString()
	seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	require.Len(t, executor.calls, 1)

	triggers, err := triggerStore.ListByScopeID(context.Background(), 42)
	require.NoError(t, err)
	require.Len(t, triggers, 1)
	assert.Greater(t, triggers[0].NextRunAt, time.Now().Unix(), "NextRunAt should be advanced to the future")
	assert.Empty(t, triggers[0].LockedBy, "lock should be released")
	assert.Zero(t, triggers[0].LastRunAt, "LastRunAt should not be set for a skipped trigger")
}

func TestProcessTick_ExecutorJobError_EmitsSingleReasonedJobError(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{err: intervalTriggerJobError("cmc_lookup_error", goerrors.New("lookup failed"))}
	statter := &counterRecorder{}
	obsv := observability.NewNoopExporters()
	obsv.Statter = statter

	agentID := uuid.NewString()
	seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	jobErrors := statter.findByKey("triggers.job_error")
	require.Len(t, jobErrors, 1, "scheduler should emit one job_error per failed trigger attempt")
	assert.Equal(t, "interval", jobErrors[0].tags["trigger_type"])
	assert.Equal(t, schedulerstore.IntervalTypeDaily, jobErrors[0].tags["interval_type"])
	assert.Equal(t, "cmc_lookup_error", jobErrors[0].tags["reason"])
}

func strPtr(s string) *string {
	return &s
}

// recordingStatter captures Distribution calls for assertions.
type recordingStatter struct {
	*observability.MockStatter

	mu            sync.Mutex
	distributions []recordedDistribution
}

type recordedDistribution struct {
	key   string
	tags  stats.Tags
	value float64
}

func (r *recordingStatter) Distribution(key string, tags stats.Tags, value float64) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.distributions = append(r.distributions, recordedDistribution{key, tags, value})
}

func (r *recordingStatter) findByKey(key string) []recordedDistribution {
	r.mu.Lock()
	defer r.mu.Unlock()
	out := make([]recordedDistribution, 0)
	for _, d := range r.distributions {
		if d.key == key {
			out = append(out, d)
		}
	}
	return out
}

func TestProcessTick_EmitsObservabilityMetrics(t *testing.T) {
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{}

	rec := &recordingStatter{MockStatter: &observability.MockStatter{}}
	obsv := observability.NewNoopExporters()
	obsv.Statter = rec

	agentID := uuid.NewString()
	// Trigger was due 5 minutes ago so the lag metric has a non-zero value.
	dueAt := time.Now().Add(-5 * time.Minute).Unix()
	seedTrigger(t, triggerStore, 42, agentID, dueAt)

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	batchSizeCalls := rec.findByKey("scheduler.tick.batch_size")
	require.Len(t, batchSizeCalls, 1, "expected one scheduler.tick.batch_size emission")
	assert.InDelta(t, float64(10), batchSizeCalls[0].value, 0.001)

	batchUsedCalls := rec.findByKey("scheduler.tick.batch_used")
	require.Len(t, batchUsedCalls, 1, "expected one scheduler.tick.batch_used emission")
	assert.InDelta(t, float64(1), batchUsedCalls[0].value, 0.001)

	lagCalls := rec.findByKey("scheduler.due_lag_seconds")
	require.Len(t, lagCalls, 1, "expected one scheduler.due_lag_seconds emission per due trigger")
	assert.GreaterOrEqual(t, lagCalls[0].value, float64(5*60-1), "lag should be ~5 minutes")
	assert.Equal(t, "interval", lagCalls[0].tags["trigger_type"])
	assert.Equal(t, schedulerstore.IntervalTypeDaily, lagCalls[0].tags["interval_type"])
}

// stubFutureTriggerStore returns a single trigger from FindDueTriggers regardless
// of the `now` filter, so we can exercise the defensive lag clamp without relying
// on the memory store's due-filtering behavior.
type stubFutureTriggerStore struct {
	*triggermemory.Store

	futureTrigger *schedulerstore.IntervalTriggerRecord
}

func (s *stubFutureTriggerStore) FindDueTriggers(_ context.Context, _ time.Time, _ int) ([]*schedulerstore.IntervalTriggerRecord, error) {
	return []*schedulerstore.IntervalTriggerRecord{s.futureTrigger}, nil
}

func TestProcessTick_DueLagClampsToZeroForFutureTriggers(t *testing.T) {
	executor := &mockExecutor{}

	rec := &recordingStatter{MockStatter: &observability.MockStatter{}}
	obsv := observability.NewNoopExporters()
	obsv.Statter = rec

	futureTrigger := &schedulerstore.IntervalTriggerRecord{
		ID:             uuid.NewString(),
		Scope:          schedulerstore.ScopeRepository,
		ScopeID:        42,
		AgentID:        uuid.NewString(),
		IntervalType:   schedulerstore.IntervalTypeDaily,
		ScatterOffset:  0.5,
		NextRunAt:      time.Now().Add(time.Hour).Unix(),
		ActorID:        200,
		ActorLogin:     "pusher",
		RepoID:         42,
		RepoOwnerID:    100,
		RepoOwnerLogin: "my-org",
		RepoName:       "my-repo",
		TreeOID:        "abc123",
	}
	store := &stubFutureTriggerStore{Store: triggermemory.NewStore(), futureTrigger: futureTrigger}

	s := New(
		store, executor,
		NewDefaultSchedulingHook(10), nil,
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	lagCalls := rec.findByKey("scheduler.due_lag_seconds")
	require.Len(t, lagCalls, 1, "lag metric should still fire for a future trigger (defensive clamp covers clock skew)")
	assert.InDelta(t, float64(0), lagCalls[0].value, 0.001, "lag must clamp to 0 when next_run_at is in the future")
	assert.Equal(t, schedulerstore.IntervalTypeDaily, lagCalls[0].tags["interval_type"])
}

// stubEnvRouter accepts or rejects all triggers; used to exercise the gate path.
type stubEnvRouter struct {
	allow bool
}

func (s *stubEnvRouter) ShouldProcess(_ context.Context, _, _, _ int64) bool {
	return s.allow
}

func TestProcessTick_EnvRouting_SkipsWhenRouterRejects(t *testing.T) {
	// Router rejects this stamp's processing → trigger is skipped without acquiring a lock or executing.
	triggerStore := triggermemory.NewStore()
	executor := &mockExecutor{}
	obsv := observability.NewNoopExporters()

	agentID := uuid.NewString()
	seedTrigger(t, triggerStore, 42, agentID, time.Now().Add(-time.Hour).Unix())

	s := New(
		triggerStore, executor,
		NewDefaultSchedulingHook(10), &stubEnvRouter{allow: false},
		obsv, "worker-1", time.Minute, time.Minute, 5*time.Minute,
	)

	s.processTick(context.Background())

	require.Empty(t, executor.calls, "executor must not be invoked when env-routing rejects the trigger")

	triggers, err := triggerStore.ListByScopeID(context.Background(), 42)
	require.NoError(t, err)
	require.Len(t, triggers, 1)
	assert.Empty(t, triggers[0].LockedBy, "lock must not be acquired when env-routing rejects")
	assert.Zero(t, triggers[0].LockedAt)
}
