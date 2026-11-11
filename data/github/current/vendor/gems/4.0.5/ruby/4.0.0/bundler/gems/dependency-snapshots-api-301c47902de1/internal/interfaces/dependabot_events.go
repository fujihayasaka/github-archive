package interfaces

import (
	"context"
	"database/sql"
	"time"

	"github.com/github/dependency-snapshots-api/internal/ecosystems"
)

// EventType represents the type of dependabot snapshot event.
type EventType string

const (
	EventTypeInit EventType = "init"
	EventTypePush EventType = "push"
)

// ReadinessReason describes why an event is or isn't ready.
type ReadinessReason int

const (
	ReadinessReasonUnspecified ReadinessReason = iota
	// No snapshots were requested for this event.
	ReadinessReasonNoEvent
	// Some snapshots are still pending within their deadline.
	ReadinessReasonPending
	// All requested snapshots have been received.
	ReadinessReasonSnapshotComplete
	// The deadline has passed and some but not all snapshots were received.
	ReadinessReasonDeadlinePastPartialSnapshot
	// The deadline has passed and no snapshots were received.
	ReadinessReasonDeadlinePastNoSnapshot
)

// ReadinessResult holds the result of a readiness check.
type ReadinessResult struct {
	Ready     bool
	Reason    ReadinessReason
	Requested int
	Received  int
	Expired   int
	Pending   int
}

// DependabotRequestedSnapshot represents a single ecosystem+manifest snapshot we have requested.
type DependabotRequestedSnapshot struct {
	ID           uint64       `db:"id"`
	Ecosystem    string       `db:"ecosystem"`
	ManifestPath string       `db:"manifest_path_display"`
	ReceivedAt   sql.NullTime `db:"received_at"`
	Deadline     time.Time    `db:"deadline"`
}

// DependabotEvent represents a dependabot snapshot event.
type DependabotEvent struct {
	ID        uint64
	EventType EventType
	Readiness EventReadinessCounts
}

// EventReadinessCounts holds aggregate counts for evaluating event readiness.
type EventReadinessCounts struct {
	Total    int `db:"total"`
	Received int `db:"received"`
	Expired  int `db:"expired"`
}

// EvaluateReadiness determines the readiness of an event based on aggregate counts.
//
// An event with no requested snapshots is treated as ready with ReadinessReasonSnapshotComplete.
func (e *DependabotEvent) EvaluateReadiness() *ReadinessResult {
	c := &e.Readiness
	result := &ReadinessResult{
		Requested: c.Total,
		Received:  c.Received,
		Expired:   c.Expired,
		Pending:   c.Total - c.Received - c.Expired,
	}

	if c.Received+c.Expired < c.Total {
		result.Ready = false
		result.Reason = ReadinessReasonPending
	} else if c.Total == c.Received {
		result.Ready = true
		result.Reason = ReadinessReasonSnapshotComplete
	} else if c.Total == c.Expired {
		result.Ready = true
		result.Reason = ReadinessReasonDeadlinePastNoSnapshot
	} else {
		result.Ready = true
		result.Reason = ReadinessReasonDeadlinePastPartialSnapshot
	}

	return result
}

type EventQueryOptions struct {
	PushID    *uint64
	EventType *EventType
}

type EventQueryOption func(*EventQueryOptions)

func WithPushID(id uint64) EventQueryOption {
	return func(o *EventQueryOptions) {
		if id != 0 {
			o.PushID = &id
		}
	}
}

func WithEventType(et *EventType) EventQueryOption {
	return func(o *EventQueryOptions) {
		if et != nil {
			o.EventType = et
		}
	}
}

func ApplyEventQueryOptions(opts ...EventQueryOption) EventQueryOptions {
	options := EventQueryOptions{}
	for _, opt := range opts {
		opt(&options)
	}
	return options
}

// DependabotEventService provides operations to create, update and check tracking records for inidividual pushes/inits.
type DependabotEventService interface {
	CheckDependabotEventReadiness(ctx context.Context, repositoryID uint64, eventType EventType, ref string, sha string, opts ...EventQueryOption) (*ReadinessResult, error)
	CheckRepositoryReadiness(ctx context.Context, repositoryID uint64, eventType *EventType) (*ReadinessResult, error)
	CheckEventReadiness(ctx context.Context, eventID uint64) (*ReadinessResult, error)
	RecordDependabotEvent(ctx context.Context, repositoryID uint64, eventType EventType, ref string, sha string, pushID *uint64, entries []DependabotRequestedSnapshot) (uint64, error)
	MarkSnapshotReceived(ctx context.Context, eventID uint64, snapshotID uint64, ecosystem ecosystems.Ecosystem, manifestPath string) (bool, error)
}
