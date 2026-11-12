package dependabot

import (
	"context"
	"crypto/sha256"
	"fmt"
	"time"

	"github.com/github/dependency-snapshots-api/internal/contextlogger"
	"github.com/github/dependency-snapshots-api/internal/ecosystems"
	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/github/dependency-snapshots-api/internal/snapshots"

	"github.com/github/github-telemetry-go/kvp"
	stats "github.com/github/go-stats"
)

const metricCheckDependabotEventReadiness = "check_dependabot_event_readiness.checked"

type eventService struct {
	adapter snapshots.StorageAdapter
	statter stats.Client
}

func NewEventService(adapter snapshots.StorageAdapter, statter stats.Client) interfaces.DependabotEventService {
	return &eventService{adapter: adapter, statter: statter}
}

func (s *eventService) CheckEventReadiness(
	ctx context.Context,
	eventID uint64,
) (*interfaces.ReadinessResult, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "DependabotEventService", "CheckEventReadiness",
		kvp.Uint64("event_id", eventID),
	)
	defer ender()

	event, err := s.adapter.GetDependabotEventReadinessByID(ctx, eventID)
	if err != nil {
		return nil, err
	}

	if event == nil {
		contextlogger.Info(ctx, "CheckEventReadiness: no event found",
			kvp.Bool("ready", true),
			kvp.Int("reason", int(interfaces.ReadinessReasonNoEvent)),
		)
		s.statter.Counter(metricCheckDependabotEventReadiness, stats.Tags{
			"ready":  "true",
			"reason": fmt.Sprintf("%d", interfaces.ReadinessReasonNoEvent),
		}, 1)
		return &interfaces.ReadinessResult{
			Ready:  true,
			Reason: interfaces.ReadinessReasonNoEvent,
		}, nil
	}

	return evaluateEventReadiness(ctx, s.statter, event), nil
}

func (s *eventService) CheckRepositoryReadiness(
	ctx context.Context,
	repositoryID uint64,
	eventType *interfaces.EventType,
) (*interfaces.ReadinessResult, *interfaces.DependabotEvent, error) {
	eventTypeStr := "any"
	if eventType != nil {
		eventTypeStr = string(*eventType)
	}

	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "DependabotEventService", "CheckRepositoryReadiness",
		kvp.Int64("gh.repo.id", int64(repositoryID)),
		kvp.String("event_type", eventTypeStr),
	)
	defer ender()

	event, err := s.adapter.GetMostRecentDependabotEventReadiness(ctx, repositoryID, interfaces.WithEventType(eventType))
	if err != nil {
		return nil, nil, err
	}

	// TODO(brrygrdn): Revise this behaviour?
	//
	// We are currently designing on a sparse write behaviour, i.e. no event
	// is written if DS-API determines no Parse Once ecosystems are involved.
	//
	// On the assumption that gh/gh will _always_ call when our feature is enabled
	// this means we should treat the an absent event row as implicitly ready.
	//
	// This is hard to reason about and it may make more sense to either:
	// - Add a row for every event with manifest changes
	// - Provide a token to the alerting job in gh/gh to only check when
	//   Parse Once ecosystems are involved
	//
	// In either case, we would then change a missing event to mean not ready.
	//
	// See:
	// - https://github.com/github/dependency-graph/issues/9671
	if event == nil {
		contextlogger.Info(ctx, "CheckRepositoryReadiness: no event found",
			kvp.Bool("ready", true),
			kvp.Int("reason", int(interfaces.ReadinessReasonNoEvent)),
			kvp.String("event_type", eventTypeStr),
		)
		s.statter.Counter(metricCheckDependabotEventReadiness, stats.Tags{
			"ready":      "true",
			"reason":     fmt.Sprintf("%d", interfaces.ReadinessReasonNoEvent),
			"event_type": eventTypeStr,
		}, 1)
		return &interfaces.ReadinessResult{
			Ready:  true,
			Reason: interfaces.ReadinessReasonNoEvent,
		}, nil, nil
	}

	return evaluateEventReadiness(ctx, s.statter, event), event, nil
}

// MarkSnapshotReceived marks a requested snapshot entry as received for a given event, ecosystem and manifest path.
func (s *eventService) MarkSnapshotReceived(ctx context.Context, eventID uint64, snapshotID uint64, ecosystem ecosystems.Ecosystem, manifestPath string) (bool, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "DependabotEventService", "MarkSnapshotReceived",
		kvp.Uint64("event_id", eventID),
		kvp.Int64("snapshot_id", int64(snapshotID)),
		kvp.String("ecosystem", ecosystem.String()),
		kvp.String("manifest_path", manifestPath),
	)
	defer ender()

	manifestPathHash := fmt.Sprintf("%x", sha256.Sum256([]byte(manifestPath)))

	rowsAffected, err := s.adapter.MarkDependabotSnapshotReceived(ctx, eventID, ecosystem.String(), manifestPathHash, snapshotID)
	if err != nil {
		contextlogger.Warn(ctx, "MarkSnapshotReceived: failed to mark snapshot received",
			kvp.String("exception.message", err.Error()),
		)
		s.statter.Counter("mark_snapshot_received.error", stats.Tags{"ecosystem": ecosystem.String()}, 1)
		return false, err
	}

	if rowsAffected == 0 {
		contextlogger.Warn(ctx, "MarkSnapshotReceived: no matching requested snapshot found")
		s.statter.Counter("mark_snapshot_received.no_match", stats.Tags{"ecosystem": ecosystem.String()}, 1)
		return false, nil
	}

	s.statter.Counter("mark_snapshot_received.matched", stats.Tags{"ecosystem": ecosystem.String()}, 1)
	return true, nil
}

// GetEventDeadline retrieves the deadline for a given event's requested snapshots.
func (s *eventService) GetEventDeadline(ctx context.Context, eventID uint64) (time.Time, bool, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "DependabotEventService", "GetEventDeadline",
		kvp.Uint64("event_id", eventID),
	)
	defer ender()

	return s.adapter.GetEventDeadline(ctx, eventID)
}

func (s *eventService) RecordDependabotEvent(ctx context.Context, repositoryID uint64, eventType interfaces.EventType, ref string, sha string, pushID *uint64, entries []interfaces.DependabotRequestedSnapshot) (uint64, error) {
	ctx, ender, _ := contextlogger.LogStartAndStop(ctx, "DependabotEventService", "RecordDependabotEvent",
		kvp.Int64("gh.repo.id", int64(repositoryID)),
		kvp.String("event_type", string(eventType)),
		kvp.Int("num_entries", len(entries)),
	)
	defer ender()

	return s.adapter.RecordDependabotEvent(ctx, repositoryID, eventType, ref, sha, pushID, entries)
}

func evaluateEventReadiness(ctx context.Context, statter stats.Client, event *interfaces.DependabotEvent) *interfaces.ReadinessResult {
	result := event.EvaluateReadiness()

	contextlogger.Info(ctx, "CheckDependabotEventReadiness: complete",
		kvp.Int64("event_id", int64(event.ID)),
		kvp.String("event_type", string(event.EventType)),
		kvp.Bool("ready", result.Ready),
		kvp.Int("reason", int(result.Reason)),
		kvp.Int("snapshots.requested", result.Requested),
		kvp.Int("snapshots.received", result.Received),
		kvp.Int("snapshots.expired", result.Expired),
		kvp.Int("snapshots.pending", result.Pending),
	)

	statter.Counter(metricCheckDependabotEventReadiness, stats.Tags{
		"ready":      fmt.Sprintf("%t", result.Ready),
		"reason":     fmt.Sprintf("%d", result.Reason),
		"event_type": string(event.EventType),
	}, 1)

	return result
}
