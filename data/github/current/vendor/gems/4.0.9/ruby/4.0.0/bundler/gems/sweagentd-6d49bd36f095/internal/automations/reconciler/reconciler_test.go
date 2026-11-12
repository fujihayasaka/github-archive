package reconciler

import (
	"context"
	"testing"
	"time"

	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	cmcv0 "github.com/github/hydro-schemas-go/hydro/schemas/copilot_mission_control/v0"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/scheduler"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	schedulermemory "github.com/github/sweagentd/internal/scheduler/store/memory"
	"github.com/stretchr/testify/require"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	testOwnerID      int64 = 5678
	testRepoID       int64 = 1234
	testAutomationID       = "auto-1"
	testUserID       int64 = 42
	testUserLogin          = "octocat"
)

// stubEnvRouter accepts or rejects all events; used to exercise the gate path.
type stubEnvRouter struct {
	allow bool
}

func (s *stubEnvRouter) ShouldProcess(_ context.Context, _, _, _ int64) bool {
	return s.allow
}

// counterRecorder captures counter increments for assertion.
type counterRecorder struct {
	stats.NullClient

	calls []counterCall
}

type counterCall struct {
	key   string
	tags  stats.Tags
	value int64
}

func (s *counterRecorder) Counter(key string, tags stats.Tags, value int64) {
	s.calls = append(s.calls, counterCall{key, tags, value})
}

func (s *counterRecorder) findByKey(key string) []counterCall {
	var matching []counterCall
	for _, c := range s.calls {
		if c.key == key {
			matching = append(matching, c)
		}
	}
	return matching
}

// newHandler builds a Handler wired against the in-memory scheduler store.
func newHandler(t *testing.T) (*Handler, *schedulermemory.Store, *counterRecorder) {
	t.Helper()
	store := schedulermemory.NewStore()
	recorder := &counterRecorder{}
	obsv := observability.NewNoopExporters()
	obsv.Statter = recorder
	h := NewHandler(store, &stubEnvRouter{allow: true}, scheduler.NewDefaultSchedulingHook(10), obsv)
	return h, store, recorder
}

// lifecycleEvent builds a lifecycle event with sensible defaults.
type lifecycleOpts struct {
	action       cmcv0.AutomationLifecycleChanged_Action
	automationID string
	disabled     *bool
	schedules    []*cmcv0.AutomationLifecycleChanged_IntervalSchedule
	userID       int64
	userLogin    string
	updatedAt    time.Time
}

func defaultLifecycle(automationID string) lifecycleOpts {
	return lifecycleOpts{
		action:       cmcv0.AutomationLifecycleChanged_ACTION_CHANGED, //nolint:staticcheck // SA1019: exercises deprecated-action backward-compat path
		automationID: automationID,
		userID:       testUserID,
		userLogin:    testUserLogin,
		updatedAt:    time.Date(2026, 5, 19, 12, 0, 0, 0, time.UTC),
	}
}

func newLifecycleMessage(t *testing.T, opts lifecycleOpts) hydro_lib.Message {
	t.Helper()
	event := &cmcv0.AutomationLifecycleChanged{
		AutomationId:      opts.automationID,
		Action:            opts.action,
		RepositoryId:      testRepoID,
		OwnerId:           testOwnerID,
		UserId:            opts.userID,
		UserLogin:         opts.userLogin,
		IntervalSchedules: opts.schedules,
	}
	if opts.disabled != nil {
		event.Disabled = wrapperspb.Bool(*opts.disabled)
	}
	if !opts.updatedAt.IsZero() {
		event.UpdatedAt = timestamppb.New(opts.updatedAt)
	}
	payload, err := proto.Marshal(event)
	require.NoError(t, err)

	env, err := proto.Marshal(&hydro_pb.Envelope{
		TypeUrl: "test",
		Message: payload,
	})
	require.NoError(t, err)

	return hydro_lib.Message{
		Topic: topics.AutomationLifecycleChanged,
		Value: env,
	}
}

// scheduleFor builds an IntervalSchedule with the given cadence and
// optional anchors. Pass nil for unset anchors.
func scheduleFor(cadence cmcv0.AutomationLifecycleChanged_IntervalSchedule_Cadence, hourUTC, dayOfWeek *int32) *cmcv0.AutomationLifecycleChanged_IntervalSchedule {
	s := &cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		Cadence: cadence,
	}
	if hourUTC != nil {
		s.AnchorHourUtc = wrapperspb.Int32(*hourUTC)
	}
	if dayOfWeek != nil {
		s.AnchorDayOfWeek = wrapperspb.Int32(*dayOfWeek)
	}
	return s
}

func i32(v int32) *int32   { return &v }
func boolPtr(b bool) *bool { return &b }

func seededRecord(automationID, intervalType string) *schedulerstore.IntervalTriggerRecord {
	return &schedulerstore.IntervalTriggerRecord{
		ID:           "seed-" + automationID,
		Scope:        schedulerstore.ScopeRepository,
		ScopeID:      testRepoID,
		AgentID:      automationID,
		IntervalType: intervalType,
		NextRunAt:    1,
		ActorID:      testUserID,
		ActorLogin:   testUserLogin,
		RepoID:       testRepoID,
		RepoOwnerID:  testOwnerID,
		CreatedAt:    1,
	}
}

// --- Anchor & identity propagation (the central reason this PR exists) ---

func TestDispatch_Changed_WeeklyWithAnchors_PersistsAllFields(t *testing.T) {
	h, store, _ := newHandler(t)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(
			cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_WEEKLY,
			i32(22), // hour_utc
			i32(3),  // day_of_week (Wednesday)
		),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	r := records[0]
	require.Equal(t, "weekly", r.IntervalType, "cadence must map to interval type")
	require.NotNil(t, r.AnchorHourUTC, "hour anchor must survive event → record")
	require.Equal(t, 22, *r.AnchorHourUTC)
	require.NotNil(t, r.AnchorDayOfWeek, "day anchor must survive event → record")
	require.Equal(t, 3, *r.AnchorDayOfWeek)
	require.Equal(t, testUserID, r.ActorID, "actor id must come from event UserId")
	require.Equal(t, testUserLogin, r.ActorLogin, "actor login must come from event UserLogin")
	require.NotZero(t, r.NextRunAt, "NextRunAt must be initialized for new records")
	require.NotZero(t, r.ScatterOffset, "ScatterOffset must be initialized for new records")
}

func TestDispatch_Changed_HourlyOmitsAnchors_PersistsCadenceOnly(t *testing.T) {
	h, store, _ := newHandler(t)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_HOURLY, nil, nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "hourly", records[0].IntervalType)
	require.Nil(t, records[0].AnchorHourUTC, "hourly must not carry an hour anchor")
	require.Nil(t, records[0].AnchorDayOfWeek, "hourly must not carry a day anchor")
}

func TestDispatch_HourlyOmitsAnchors_PersistsCadenceOnly_AllChangeActions(t *testing.T) {
	changeActions := map[string]cmcv0.AutomationLifecycleChanged_Action{
		"changed": cmcv0.AutomationLifecycleChanged_ACTION_CHANGED, //nolint:staticcheck // SA1019: exercises deprecated-action backward-compat path
		"created": cmcv0.AutomationLifecycleChanged_ACTION_CREATED,
		"updated": cmcv0.AutomationLifecycleChanged_ACTION_UPDATED,
	}
	for name, action := range changeActions {
		t.Run(name, func(t *testing.T) {
			h, store, _ := newHandler(t)

			opts := defaultLifecycle(testAutomationID)
			opts.action = action
			opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
				scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_HOURLY, nil, nil),
			}

			err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
			require.NoError(t, err)

			records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
			require.NoError(t, err)
			require.Len(t, records, 1, "every change-style action must materialize an interval record")
			require.Equal(t, "hourly", records[0].IntervalType)
		})
	}
}

func TestDispatch_UnknownAction_AcksWithoutRecord(t *testing.T) {
	h, store, recorder := newHandler(t)

	opts := defaultLifecycle(testAutomationID)
	opts.action = cmcv0.AutomationLifecycleChanged_ACTION_UNKNOWN
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_HOURLY, nil, nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records, "unknown action must not write a record")
	require.NotEmpty(t, recorder.findByKey("reconciler.unknown_action"))
}

func TestDispatch_Changed_DailyWithHourAnchorOnly(t *testing.T) {
	h, store, _ := newHandler(t)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, i32(9), nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "daily", records[0].IntervalType)
	require.NotNil(t, records[0].AnchorHourUTC)
	require.Equal(t, 9, *records[0].AnchorHourUTC)
	require.Nil(t, records[0].AnchorDayOfWeek, "daily must not carry a day anchor")
}

// --- Disable handling ---

func TestDispatch_Changed_DisabledTrue_DeletesExistingRecord(t *testing.T) {
	// Disable arrives as CHANGED with Disabled=true and is treated as delete.
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.disabled = boolPtr(true)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, i32(9), nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records, "Disabled=true must delete the local record")
}

func TestDispatch_Changed_DisabledFalse_RoutesNormally(t *testing.T) {
	// Disabled=false (explicitly set) must not divert from the normal path.
	h, store, _ := newHandler(t)

	opts := defaultLifecycle(testAutomationID)
	opts.disabled = boolPtr(false)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, nil, nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
}

// --- Schedule absence / unknown cadence ---

func TestDispatch_Changed_NoIntervalSchedules_DeletesExistingRecord(t *testing.T) {
	// Empty IntervalSchedules means no scheduling interest; delete the record.
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	// opts.schedules is nil

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records, "no IntervalSchedules must delete the local record")
}

func TestDispatch_Changed_UnknownCadence_DeletesExistingRecord(t *testing.T) {
	// CADENCE_UNKNOWN means "skip this schedule"; if it's the only one, delete.
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_UNKNOWN, nil, nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records, "CADENCE_UNKNOWN must be skipped")
}

// --- Patch path: existing record gets updated, scatter is preserved ---

func TestDispatch_Changed_CadenceUpdate_PatchesAndPreservesScatter(t *testing.T) {
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	const seededScatter = 0.42
	seeded.ScatterOffset = seededScatter
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(
			cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_WEEKLY,
			i32(22), i32(3),
		),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "weekly", records[0].IntervalType)
	require.NotNil(t, records[0].AnchorHourUTC)
	require.Equal(t, 22, *records[0].AnchorHourUTC)
	require.NotNil(t, records[0].AnchorDayOfWeek)
	require.Equal(t, 3, *records[0].AnchorDayOfWeek)
	require.InEpsilon(t, seededScatter, records[0].ScatterOffset, 0.0001,
		"scatter offset must be preserved across schedule patches to keep concurrent repos de-correlated")
}

func TestDispatch_Changed_AnchorOnlyChange_PatchesAnchorsAndNextRun(t *testing.T) {
	// User keeps weekly cadence but moves the anchor from Wed 22:00 to Thu 09:00.
	// Verify both anchors update and next_run_at is recomputed.
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "weekly")
	originalHour, originalDay := 22, 3
	seeded.AnchorHourUTC = &originalHour
	seeded.AnchorDayOfWeek = &originalDay
	seeded.NextRunAt = 1_000_000
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(
			cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_WEEKLY,
			i32(9), i32(4),
		),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.NotNil(t, records[0].AnchorHourUTC)
	require.Equal(t, 9, *records[0].AnchorHourUTC)
	require.NotNil(t, records[0].AnchorDayOfWeek)
	require.Equal(t, 4, *records[0].AnchorDayOfWeek)
	require.NotEqual(t, int64(1_000_000), records[0].NextRunAt, "next_run_at must be recomputed when the schedule shape changes")
}

func TestDispatch_Changed_NoChange_DoesNotPatch(t *testing.T) {
	// Identical event arriving twice (or a no-op CHANGED) must not write to
	// the store. This keeps Cosmos RU consumption flat under repeated emits.
	h, store, recorder := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	hour := 9
	seeded.AnchorHourUTC = &hour
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, i32(9), nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	require.NotEmpty(t, recorder.findByKey("reconciler.automation_triggers_unchanged"))
}

// --- Stale event ordering (R2) ---

func TestDispatch_Changed_StaleEvent_IgnoredOnExistingRecord(t *testing.T) {
	// Record was last materialised at t=12:00. A stale CHANGED with t=11:00
	// arriving after must be dropped — applying it would revert the record.
	h, store, recorder := newHandler(t)

	seeded := seededRecord(testAutomationID, "weekly")
	hour, day := 9, 1
	seeded.AnchorHourUTC = &hour
	seeded.AnchorDayOfWeek = &day
	seeded.LastEventUpdatedAt = time.Date(2026, 5, 19, 12, 0, 0, 0, time.UTC).UnixMicro()
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.updatedAt = time.Date(2026, 5, 19, 11, 0, 0, 0, time.UTC)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, i32(22), nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "weekly", records[0].IntervalType, "stale CHANGED must not revert cadence")
	require.NotEmpty(t, recorder.findByKey("reconciler.event_stale"))
}

func TestDispatch_Deleted_StaleEvent_IgnoredOnExistingRecord(t *testing.T) {
	// Record was last materialised at t=12:00. A stale DELETED with t=11:00
	// arriving after must be dropped — deleting would lose the live record.
	h, store, recorder := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	seeded.LastEventUpdatedAt = time.Date(2026, 5, 19, 12, 0, 0, 0, time.UTC).UnixMicro()
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.action = cmcv0.AutomationLifecycleChanged_ACTION_DELETED
	opts.updatedAt = time.Date(2026, 5, 19, 11, 0, 0, 0, time.UTC)

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1, "stale DELETED must not remove a live record")
	require.NotEmpty(t, recorder.findByKey("reconciler.event_stale"))
}

func TestDispatch_Changed_FreshEventOverridesStale(t *testing.T) {
	// Newer event must be applied; new LastEventUpdatedAt must be persisted
	// so a subsequent stale event would be dropped.
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "daily")
	seeded.LastEventUpdatedAt = time.Date(2026, 5, 19, 10, 0, 0, 0, time.UTC).UnixMicro()
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.updatedAt = time.Date(2026, 5, 19, 12, 0, 0, 0, time.UTC)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_WEEKLY, i32(22), i32(3)),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "weekly", records[0].IntervalType)
	require.Equal(t, opts.updatedAt.UnixMicro(), records[0].LastEventUpdatedAt,
		"LastEventUpdatedAt must advance so the next stale event will be dropped")
}

// --- Anchor clearing (R4) ---

func TestDispatch_Changed_WeeklyToDaily_ClearsDayAnchor(t *testing.T) {
	// Weekly→daily transition drops day_of_week; verify re-upsert clears it.
	h, store, recorder := newHandler(t)

	seeded := seededRecord(testAutomationID, "weekly")
	hour, day := 22, 3
	seeded.AnchorHourUTC = &hour
	seeded.AnchorDayOfWeek = &day
	const seededScatter = 0.42
	seeded.ScatterOffset = seededScatter
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, i32(9), nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "daily", records[0].IntervalType)
	require.NotNil(t, records[0].AnchorHourUTC)
	require.Equal(t, 9, *records[0].AnchorHourUTC)
	require.Nil(t, records[0].AnchorDayOfWeek, "day_of_week must be cleared on weekly→daily transition")
	require.InEpsilon(t, seededScatter, records[0].ScatterOffset, 0.0001, "scatter offset must be preserved")
	require.NotEmpty(t, recorder.findByKey("reconciler.automation_triggers_updated"))
}

func TestDispatch_Changed_WeeklyToHourly_ClearsBothAnchors(t *testing.T) {
	h, store, _ := newHandler(t)

	seeded := seededRecord(testAutomationID, "weekly")
	hour, day := 22, 3
	seeded.AnchorHourUTC = &hour
	seeded.AnchorDayOfWeek = &day
	_, err := store.Upsert(context.Background(), seeded)
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_HOURLY, nil, nil),
	}

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Equal(t, "hourly", records[0].IntervalType)
	require.Nil(t, records[0].AnchorHourUTC, "hour anchor must be cleared on transition to hourly")
	require.Nil(t, records[0].AnchorDayOfWeek, "day anchor must be cleared on transition to hourly")
}

// --- Delete action ---

func TestDispatch_Deleted_RemovesRecord(t *testing.T) {
	h, store, _ := newHandler(t)

	_, err := store.Upsert(context.Background(), seededRecord(testAutomationID, "daily"))
	require.NoError(t, err)

	opts := defaultLifecycle(testAutomationID)
	opts.action = cmcv0.AutomationLifecycleChanged_ACTION_DELETED

	err = h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records)
}

func TestDispatch_Deleted_NoRecordToDelete_IsIdempotent(t *testing.T) {
	h, _, _ := newHandler(t)

	opts := defaultLifecycle("never-existed")
	opts.action = cmcv0.AutomationLifecycleChanged_ACTION_DELETED

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err, "deleting a non-existent record must be a no-op, not an error")
}

// --- Topic guard, malformed payloads ---

func TestDispatch_UnexpectedTopic_AcksAndDoesNothing(t *testing.T) {
	h, store, _ := newHandler(t)

	msg := newLifecycleMessage(t, defaultLifecycle(testAutomationID))
	msg.Topic = "some.other.topic"

	err := h.Dispatch(context.Background(), msg)
	require.NoError(t, err)
	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records)
}

func TestDispatch_MalformedEnvelope_AcksWithMetric(t *testing.T) {
	h, _, recorder := newHandler(t)

	err := h.Dispatch(context.Background(), hydro_lib.Message{
		Topic: topics.AutomationLifecycleChanged,
		Value: []byte("not-a-proto-envelope"),
	})
	require.NoError(t, err, "malformed payloads must be acked, not retried")
	require.NotEmpty(t, recorder.findByKey("reconciler.envelope_error"))
}

func TestDispatch_EmptyAutomationID_AcksWithMetric(t *testing.T) {
	h, _, recorder := newHandler(t)

	opts := defaultLifecycle("")
	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)
	require.NotEmpty(t, recorder.findByKey("reconciler.decode_error"))
}

// --- Environment routing gate ---

func TestDispatch_EnvRouting_SkipsWhenRouterRejects(t *testing.T) {
	// Router says "this stamp doesn't own this event" → reconciler skips, no Cosmos write.
	store := schedulermemory.NewStore()
	recorder := &counterRecorder{}
	obsv := observability.NewNoopExporters()
	obsv.Statter = recorder
	h := NewHandler(store, &stubEnvRouter{allow: false}, scheduler.NewDefaultSchedulingHook(10), obsv)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, nil, nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err, "rejected events must ack cleanly, not error")

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Empty(t, records, "store must remain untouched when env routing rejects the event")
	require.NotEmpty(t, recorder.findByKey("reconciler.event_skipped_env_routing"))
}

func TestDispatch_EnvRouting_DoesNotGateWhenRouterAllows(t *testing.T) {
	// Router allows → reconciler processes the event normally.
	store := schedulermemory.NewStore()
	recorder := &counterRecorder{}
	obsv := observability.NewNoopExporters()
	obsv.Statter = recorder
	h := NewHandler(store, &stubEnvRouter{allow: true}, scheduler.NewDefaultSchedulingHook(10), obsv)

	opts := defaultLifecycle(testAutomationID)
	opts.schedules = []*cmcv0.AutomationLifecycleChanged_IntervalSchedule{
		scheduleFor(cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY, nil, nil),
	}

	err := h.Dispatch(context.Background(), newLifecycleMessage(t, opts))
	require.NoError(t, err)

	records, err := store.GetByAgentID(context.Background(), testRepoID, testAutomationID)
	require.NoError(t, err)
	require.Len(t, records, 1)
	require.Empty(t, recorder.findByKey("reconciler.event_skipped_env_routing"))
}
