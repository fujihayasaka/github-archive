// Package reconciler consumes copilot_mission_control.v0.AutomationLifecycleChanged
// Hydro events and materializes interval-trigger records into the scheduler's
// CosmosDB store. Driven entirely from the event payload — no per-event Twirp
// callback to CMC.
package reconciler

import (
	"context"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
	"github.com/github/github-telemetry-go/kvp"
	"github.com/github/go-http/v2/middleware/requestid"
	"github.com/github/go-stats"
	hydro_pb "github.com/github/hydro-client-go/v7/generated/hydro/v1"
	hydro_lib "github.com/github/hydro-client-go/v7/pkg/hydro"
	cmcv0 "github.com/github/hydro-schemas-go/hydro/schemas/copilot_mission_control/v0"
	"github.com/github/sweagentd/internal/envrouting"
	"github.com/github/sweagentd/internal/events/hydro/topics"
	"github.com/github/sweagentd/internal/goerrors"
	"github.com/github/sweagentd/internal/observability"
	"github.com/github/sweagentd/internal/requestctx"
	"github.com/github/sweagentd/internal/scheduler"
	schedulerstore "github.com/github/sweagentd/internal/scheduler/store"
	"github.com/google/uuid"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

// IntervalTriggerStore is the subset of scheduler-store operations the
// reconciler needs.
type IntervalTriggerStore interface {
	Upsert(ctx context.Context, trigger *schedulerstore.IntervalTriggerRecord) (*schedulerstore.IntervalTriggerRecord, error)
	Get(ctx context.Context, scopeID int64, id string) (*schedulerstore.IntervalTriggerRecord, error)
	Delete(ctx context.Context, scopeID int64, id string) error
	GetByAgentID(ctx context.Context, scopeID int64, agentID string) ([]*schedulerstore.IntervalTriggerRecord, error)
	PatchTrigger(ctx context.Context, scopeID int64, id string, patch schedulerstore.IntervalTriggerPatch) (*azcore.ETag, error)
}

// EnvRouter gates event processing by environment to prevent cross-stamp duplicate writes.
type EnvRouter interface {
	ShouldProcess(ctx context.Context, actorID, repoID, ownerID int64) bool
}

// Handler dispatches AutomationLifecycleChanged Hydro events into
// IntervalTriggerRecord upserts and deletes.
type Handler struct {
	store          IntervalTriggerStore
	envRouter      EnvRouter
	schedulingHook scheduler.SchedulingHook
	obsv           observability.Exporters
}

// NewHandler creates a reconciler Handler. The scheduling hook is used to
// compute initial NextRunAt for newly created trigger records.
func NewHandler(store IntervalTriggerStore, envRouter EnvRouter, schedulingHook scheduler.SchedulingHook, obsv observability.Exporters) *Handler {
	return &Handler{
		store:          store,
		envRouter:      envRouter,
		schedulingHook: schedulingHook,
		obsv:           obsv,
	}
}

// Compile-time check that envrouting.Router satisfies EnvRouter.
var _ EnvRouter = (*envrouting.Router)(nil)

// Dispatch is the Hydro MessageHandler entry point.
func (h *Handler) Dispatch(ctx context.Context, m hydro_lib.Message) error {
	if requestID := requestid.GetGitHubRequestID(ctx); requestID == "" {
		ctx = requestid.WithNewGitHubRequestID(ctx)
	}

	ctx = requestctx.AddData(ctx, &requestctx.CtxData{
		HydroMessage: &requestctx.HydroEvent{
			Topic:     m.Topic,
			Partition: m.Partition,
			Offset:    m.Offset,
		},
	})

	logger := h.obsv.LoggerWithTelemetry(ctx)

	if m.Topic != topics.AutomationLifecycleChanged {
		logger.Error("unexpected topic in automation reconciler",
			kvp.String("topic", m.Topic),
		)
		return nil
	}

	var envelope hydro_pb.Envelope
	err := proto.Unmarshal(m.Value, &envelope)
	if err != nil {
		logger.WithError(err).Error("reconciler: failed to unmarshal envelope")
		h.obsv.Increment(ctx, "reconciler.envelope_error", nil)
		return nil
	}

	requestctx.Data(ctx).HydroMessage.EnvelopeID = envelope.Id

	event := &cmcv0.AutomationLifecycleChanged{}
	err = proto.Unmarshal(envelope.GetMessage(), event)
	if err != nil {
		logger.WithError(err).Error("reconciler: failed to unmarshal AutomationLifecycleChanged")
		h.obsv.Increment(ctx, "reconciler.decode_error", nil)
		return nil
	}

	h.obsv.Increment(ctx, "reconciler.event_received", stats.Tags{
		"action": event.GetAction().String(),
	})

	if event.GetAutomationId() == "" {
		logger.Error("reconciler: event has empty automation_id")
		h.obsv.Increment(ctx, "reconciler.decode_error", nil)
		return nil
	}

	_ = requestctx.AddRepo(ctx, requestctx.CtxRepo{
		ID:      event.GetRepositoryId(),
		OwnerID: event.GetOwnerId(),
	})
	logger = h.obsv.LoggerWithTelemetry(ctx)

	// Pairs with copilot-mission-control's "published AutomationLifecycleChanged"
	// log via shared automation_id for end-to-end Splunk tracing.
	logger.Info("reconciler: received automation lifecycle event",
		kvp.String("automation_id", event.GetAutomationId()),
		kvp.String("action", event.GetAction().String()),
		kvp.Int64("repo_id", event.GetRepositoryId()),
		kvp.Int64("owner_id", event.GetOwnerId()),
		kvp.Int("interval_schedule_count", len(event.GetIntervalSchedules())),
		kvp.Bool("disabled", event.GetDisabled().GetValue()),
	)

	// reconciler.event_age_ms measures end-to-end propagation lag from when CMC
	// recorded the change (event.UpdatedAt) to when sweagentd processes it.
	// A growing age means our local interval-trigger view is stale.
	if updatedAt := event.GetUpdatedAt(); updatedAt != nil {
		h.obsv.DistributionMs(ctx, "reconciler.event_age_ms", stats.Tags{
			"action": event.GetAction().String(),
		}, time.Since(updatedAt.AsTime()))
	}

	start := time.Now()
	dispatchErr := h.handle(ctx, event)
	h.obsv.DistributionMs(ctx, "reconciler.dispatch_duration_ms", nil, time.Since(start))

	if dispatchErr != nil {
		logger.WithError(dispatchErr).Error("reconciler: dispatch error",
			kvp.String("automation_id", event.GetAutomationId()),
			kvp.String("action", event.GetAction().String()),
		)
		h.obsv.Increment(ctx, "reconciler.dispatch_error", stats.Tags{"action": event.GetAction().String()})
		return nil
	}

	// Mirrors reconciler.dispatch_error so dashboards can plot success rate.
	h.obsv.Increment(ctx, "reconciler.dispatch_success", stats.Tags{"action": event.GetAction().String()})
	logger.Info("reconciler: dispatched lifecycle event successfully",
		kvp.String("automation_id", event.GetAutomationId()),
		kvp.String("action", event.GetAction().String()),
	)

	return nil
}

func (h *Handler) handle(ctx context.Context, event *cmcv0.AutomationLifecycleChanged) error {
	if event.GetRepositoryId() == 0 {
		return goerrors.New("event has zero repository_id")
	}

	// Gate by environment to prevent cross-stamp duplicate writes to the shared interval-triggers container.
	if h.envRouter != nil && !h.envRouter.ShouldProcess(ctx, event.GetUserId(), event.GetRepositoryId(), event.GetOwnerId()) {
		h.obsv.Increment(ctx, "reconciler.event_skipped_env_routing", stats.Tags{"action": event.GetAction().String()})
		return nil
	}

	scopeID := event.GetRepositoryId()
	automationID := event.GetAutomationId()
	eventUpdated := eventUpdatedAtMicros(event)

	existing, err := h.findExistingRecord(ctx, scopeID, automationID)
	if err != nil {
		h.obsv.Increment(ctx, "reconciler.store_error", stats.Tags{"op": "get"})
		return goerrors.Errorf("failed to look up existing trigger record for %s: %w", automationID, err)
	}

	if isStaleEvent(existing, eventUpdated) {
		h.obsv.Increment(ctx, "reconciler.event_stale", stats.Tags{"action": event.GetAction().String()})
		return nil
	}

	switch event.GetAction() {
	// ACTION_CHANGED is deprecated but still handled for in-flight events from older CMC builds.
	case cmcv0.AutomationLifecycleChanged_ACTION_CHANGED, //nolint:staticcheck // SA1019: backward-compat for in-flight events
		cmcv0.AutomationLifecycleChanged_ACTION_CREATED,
		cmcv0.AutomationLifecycleChanged_ACTION_UPDATED:
		return h.handleChanged(ctx, event, existing, eventUpdated)
	case cmcv0.AutomationLifecycleChanged_ACTION_DELETED:
		return h.handleDeleted(ctx, scopeID, automationID, existing)
	default:
		// Unknown action (e.g. schema bump). Ack to avoid blocking the partition.
		h.obsv.Increment(ctx, "reconciler.unknown_action", stats.Tags{"action": event.GetAction().String()})
		return nil
	}
}

// handleChanged reconciles a create / update / enable / disable event. All
// materialization fields are read directly from the Hydro event payload.
func (h *Handler) handleChanged(
	ctx context.Context,
	event *cmcv0.AutomationLifecycleChanged,
	existing *schedulerstore.IntervalTriggerRecord,
	eventUpdated int64,
) error {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	scopeID := event.GetRepositoryId()
	automationID := event.GetAutomationId()

	// Disabled is modelled as delete; re-enable arrives as CHANGED disabled=false.
	if event.GetDisabled().GetValue() {
		logger.Info("reconciler: automation is disabled — deleting local record",
			kvp.String("automation_id", automationID),
		)
		return h.deleteRecord(ctx, scopeID, automationID, existing, "disabled")
	}

	schedule := firstValidSchedule(event.GetIntervalSchedules())
	if schedule == nil {
		// No interval trigger remains on the automation; treat as delete.
		logger.Info("reconciler: automation has no valid interval schedule — deleting local record",
			kvp.String("automation_id", automationID),
		)
		return h.deleteRecord(ctx, scopeID, automationID, existing, "no_valid_interval")
	}

	return h.upsertFromEvent(ctx, event, schedule, existing, eventUpdated)
}

// handleDeleted soft-deletes the local interval-trigger record for an
// automation that was deleted in CMC.
func (h *Handler) handleDeleted(ctx context.Context, scopeID int64, automationID string, existing *schedulerstore.IntervalTriggerRecord) error {
	return h.deleteRecord(ctx, scopeID, automationID, existing, "deleted")
}

// upsertFromEvent creates or updates an IntervalTriggerRecord from the event
// payload. Runtime config is resolved by the executor at fire time, not here.
func (h *Handler) upsertFromEvent(
	ctx context.Context,
	event *cmcv0.AutomationLifecycleChanged,
	schedule *cmcv0.AutomationLifecycleChanged_IntervalSchedule,
	existing *schedulerstore.IntervalTriggerRecord,
	eventUpdated int64,
) error {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	scopeID := event.GetRepositoryId()
	automationID := event.GetAutomationId()
	intervalType := intervalTypeForCadence(schedule.GetCadence())
	anchorHourUTC := optionalIntFromWrapper(schedule.GetAnchorHourUtc())
	anchorDayOfWeek := optionalIntFromWrapper(schedule.GetAnchorDayOfWeek())
	actorID := event.GetUserId()
	actorLogin := event.GetUserLogin()

	if existing == nil {
		scatter := scheduler.GenerateScatterOffset()
		now := time.Now()
		record := &schedulerstore.IntervalTriggerRecord{
			ID:                 uuid.NewString(),
			Scope:              schedulerstore.ScopeRepository,
			ScopeID:            scopeID,
			AgentID:            automationID,
			IntervalType:       intervalType,
			AnchorHourUTC:      anchorHourUTC,
			AnchorDayOfWeek:    anchorDayOfWeek,
			ScatterOffset:      scatter,
			ActorID:            actorID,
			ActorLogin:         actorLogin,
			RepoID:             scopeID,
			RepoOwnerID:        event.GetOwnerId(),
			CreatedAt:          now.Unix(),
			LastEventUpdatedAt: eventUpdated,
		}
		record.NextRunAt = scheduler.CalculateInitialNextRunAtForSchedule(record.Schedule(), scatter, h.schedulingHook).Unix()
		_, err := h.store.Upsert(ctx, record)
		if err != nil {
			h.obsv.Increment(ctx, "reconciler.store_error", stats.Tags{"op": "upsert"})
			return goerrors.Errorf("failed to upsert trigger record for %s: %w", automationID, err)
		}
		h.obsv.Increment(ctx, "reconciler.automation_triggers_created", nil)
		logger.Info("reconciler: created interval trigger record",
			kvp.String("automation_id", automationID),
			kvp.String("interval_type", intervalType),
		)
		return nil
	}

	// Cosmos PATCH can't null an omitempty field via nil; re-upsert so dropped
	// anchors (e.g. weekly→daily) actually fall out of the document.
	if anchorCleared(existing, anchorHourUTC, anchorDayOfWeek) {
		record := existing
		record.IntervalType = intervalType
		record.AnchorHourUTC = anchorHourUTC
		record.AnchorDayOfWeek = anchorDayOfWeek
		record.ActorID = actorID
		record.ActorLogin = actorLogin
		record.LastEventUpdatedAt = eventUpdated
		record.NextRunAt = scheduler.CalculateInitialNextRunAtForSchedule(record.Schedule(), existing.ScatterOffset, h.schedulingHook).Unix()
		_, err := h.store.Upsert(ctx, record)
		if err != nil {
			h.obsv.Increment(ctx, "reconciler.store_error", stats.Tags{"op": "upsert_anchor_clear"})
			return goerrors.Errorf("failed to re-upsert trigger record for %s: %w", automationID, err)
		}
		h.obsv.Increment(ctx, "reconciler.automation_triggers_updated", stats.Tags{"path": "anchor_cleared"})
		logger.Info("reconciler: re-upserted interval trigger record (anchor cleared)",
			kvp.String("automation_id", automationID),
			kvp.String("interval_type", intervalType),
		)
		return nil
	}

	patch := schedulerstore.IntervalTriggerPatch{ETag: existing.ETag, LastEventUpdatedAt: &eventUpdated}
	scheduleChanged := false
	if existing.IntervalType != intervalType {
		patch.IntervalType = &intervalType
		scheduleChanged = true
	}
	if !optionalIntEqual(existing.AnchorHourUTC, anchorHourUTC) {
		patch.AnchorHourUTC = anchorHourUTC
		scheduleChanged = true
	}
	if !optionalIntEqual(existing.AnchorDayOfWeek, anchorDayOfWeek) {
		patch.AnchorDayOfWeek = anchorDayOfWeek
		scheduleChanged = true
	}
	if scheduleChanged {
		newSchedule := schedulerstore.Schedule{
			IntervalType:    intervalType,
			AnchorHourUTC:   anchorHourUTC,
			AnchorDayOfWeek: anchorDayOfWeek,
		}
		nextRun := scheduler.CalculateInitialNextRunAtForSchedule(newSchedule, existing.ScatterOffset, h.schedulingHook).Unix()
		patch.NextRunAt = &nextRun
	}
	identityChanged := false
	if existing.ActorID != actorID {
		patch.ActorID = &actorID
		identityChanged = true
	}
	if existing.ActorLogin != actorLogin {
		patch.ActorLogin = &actorLogin
		identityChanged = true
	}
	if !scheduleChanged && !identityChanged {
		h.obsv.Increment(ctx, "reconciler.automation_triggers_unchanged", nil)
		return nil
	}

	_, err := h.store.PatchTrigger(ctx, scopeID, existing.ID, patch)
	if err != nil {
		h.obsv.Increment(ctx, "reconciler.store_error", stats.Tags{"op": "patch"})
		return goerrors.Errorf("failed to patch trigger record for %s: %w", automationID, err)
	}
	h.obsv.Increment(ctx, "reconciler.automation_triggers_updated", stats.Tags{"path": "patch"})
	logger.Info("reconciler: patched interval trigger record",
		kvp.String("automation_id", automationID),
		kvp.String("interval_type", intervalType),
	)
	return nil
}

// deleteRecord removes the local trigger record, idempotent when none exists.
func (h *Handler) deleteRecord(ctx context.Context, scopeID int64, automationID string, existing *schedulerstore.IntervalTriggerRecord, reasonTag string) error {
	logger := h.obsv.LoggerWithTelemetry(ctx)

	if existing == nil {
		h.obsv.Increment(ctx, "reconciler.automation_triggers_delete_noop", stats.Tags{"reason": reasonTag})
		return nil
	}

	err := h.store.Delete(ctx, scopeID, existing.ID)
	if err != nil {
		h.obsv.Increment(ctx, "reconciler.store_error", stats.Tags{"op": "delete"})
		return goerrors.Errorf("failed to delete trigger record %s: %w", existing.ID, err)
	}
	h.obsv.Statter.Counter("reconciler.automation_triggers_deleted",
		h.obsv.TelemetryTags(ctx).Merge(stats.Tags{"reason": reasonTag}),
		1,
	)
	logger.Info("reconciler: deleted interval trigger record",
		kvp.String("automation_id", automationID),
		kvp.String("trigger_id", existing.ID),
	)
	return nil
}

// findExistingRecord returns the single trigger record for the given
// (scope, automation ID) pair, or nil if none exists.
func (h *Handler) findExistingRecord(ctx context.Context, scopeID int64, automationID string) (*schedulerstore.IntervalTriggerRecord, error) {
	records, err := h.store.GetByAgentID(ctx, scopeID, automationID)
	if err != nil {
		return nil, err
	}
	if len(records) == 0 {
		return nil, nil
	}
	if len(records) > 1 {
		h.obsv.Increment(ctx, "reconciler.duplicate_records", nil)
		h.obsv.LoggerWithTelemetry(ctx).Warn("reconciler: multiple records for one automation_id",
			kvp.String("automation_id", automationID),
			kvp.Int("count", len(records)),
		)
	}
	return records[0], nil
}

// firstValidSchedule returns the first schedule with a supported cadence, or
// nil when none qualify.
func firstValidSchedule(schedules []*cmcv0.AutomationLifecycleChanged_IntervalSchedule) *cmcv0.AutomationLifecycleChanged_IntervalSchedule {
	for _, s := range schedules {
		if s == nil {
			continue
		}
		if intervalTypeForCadence(s.GetCadence()) == "" {
			continue
		}
		return s
	}
	return nil
}

// intervalTypeForCadence maps the Hydro cadence enum to a scheduler-store
// interval type. Returns "" for unknown cadences.
func intervalTypeForCadence(c cmcv0.AutomationLifecycleChanged_IntervalSchedule_Cadence) string {
	switch c {
	case cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_HOURLY:
		return schedulerstore.IntervalTypeHourly
	case cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_DAILY:
		return schedulerstore.IntervalTypeDaily
	case cmcv0.AutomationLifecycleChanged_IntervalSchedule_CADENCE_WEEKLY:
		return schedulerstore.IntervalTypeWeekly
	default:
		return ""
	}
}

// optionalIntFromWrapper converts an Int32Value to *int. Nil preserves the
// "no anchor set" distinction from "anchor set to zero".
func optionalIntFromWrapper(v *wrapperspb.Int32Value) *int {
	if v == nil {
		return nil
	}
	out := int(v.GetValue())
	return &out
}

// optionalIntEqual compares two *int values, treating nil == nil as equal.
func optionalIntEqual(a, b *int) bool {
	if a == nil && b == nil {
		return true
	}
	if a == nil || b == nil {
		return false
	}
	return *a == *b
}

// eventUpdatedAtMicros returns the event's UpdatedAt as UnixMicro, or 0 when
// the field is unset.
func eventUpdatedAtMicros(event *cmcv0.AutomationLifecycleChanged) int64 {
	t := event.GetUpdatedAt()
	if t == nil {
		return 0
	}
	return t.AsTime().UnixMicro()
}

// isStaleEvent reports whether eventUpdated predates the existing record's
// LastEventUpdatedAt. Returns false when either timestamp is zero.
func isStaleEvent(existing *schedulerstore.IntervalTriggerRecord, eventUpdated int64) bool {
	if existing == nil || existing.LastEventUpdatedAt == 0 || eventUpdated == 0 {
		return false
	}
	return eventUpdated < existing.LastEventUpdatedAt
}

// anchorCleared reports whether the desired anchors drop a value previously
// set on the existing record.
func anchorCleared(existing *schedulerstore.IntervalTriggerRecord, desiredHour, desiredDay *int) bool {
	return (existing.AnchorHourUTC != nil && desiredHour == nil) ||
		(existing.AnchorDayOfWeek != nil && desiredDay == nil)
}
