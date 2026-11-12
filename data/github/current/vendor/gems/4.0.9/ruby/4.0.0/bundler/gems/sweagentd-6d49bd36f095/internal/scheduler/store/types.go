// Package store provides types for interval trigger storage.
package store

import (
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azcore"
)

// Interval type constants.
const (
	IntervalTypeHourly = "hourly"
	IntervalTypeDaily  = "daily"
	IntervalTypeWeekly = "weekly"
)

// Scope constants (repo only for initial implementation).
const (
	ScopeRepository = "repo"
)

// Scatter duration windows for thundering herd prevention.
const (
	HourlyScatterDuration = 10 * time.Minute
	DailyScatterDuration  = 4 * time.Hour
	WeeklyScatterDuration = 12 * time.Hour

	// AnchoredDailyScatterDuration is the scatter window for daily schedules anchored to a UTC hour.
	AnchoredDailyScatterDuration = 15 * time.Minute
	// AnchoredWeeklyScatterDuration is the scatter window for weekly schedules anchored to a UTC weekday + hour.
	AnchoredWeeklyScatterDuration = 30 * time.Minute
	// WeeklyDayAnytimeScatterDuration is the scatter window for weekly schedules anchored to a UTC weekday only (any hour).
	WeeklyDayAnytimeScatterDuration = 24 * time.Hour
)

// ValidIntervalTypes contains the set of supported interval types.
var ValidIntervalTypes = map[string]bool{
	IntervalTypeHourly: true,
	IntervalTypeDaily:  true,
	IntervalTypeWeekly: true,
}

// Schedule is a small value type describing the shape of an interval schedule.
type Schedule struct {
	IntervalType    string
	AnchorHourUTC   *int
	AnchorDayOfWeek *int
}

// IsAnchoredHour returns true when the schedule pins a specific UTC hour.
func (s Schedule) IsAnchoredHour() bool { return s.AnchorHourUTC != nil }

// IsAnchoredDay returns true when the schedule pins a specific UTC day-of-week.
func (s Schedule) IsAnchoredDay() bool { return s.AnchorDayOfWeek != nil }

// IntervalTriggerRecord represents a scheduled trigger record in the interval-triggers Cosmos container.
type IntervalTriggerRecord struct {
	// ID is a UUID generated on creation.
	ID string `json:"id"`
	// Scope is the agent scope. Currently only "repo" is supported.
	Scope string `json:"scope"`
	// ScopeID is the CosmosDB partition key (repository ID for repo scope).
	ScopeID int64 `json:"scope_id"`
	// AgentID is the UUID of the agent config record this trigger belongs to.
	AgentID string `json:"agent_id"`
	// IntervalType is the base scheduling interval: "hourly", "daily", or "weekly".
	// Anchored variants are represented via AnchorHourUTC and AnchorDayOfWeek.
	IntervalType string `json:"interval_type"`
	// AnchorHourUTC is an optional UTC hour (0..23) the schedule is pinned to.
	AnchorHourUTC *int `json:"anchor_hour_utc,omitempty"`
	// AnchorDayOfWeek is an optional UTC day-of-week (0=Sunday..6=Saturday) the
	// schedule is pinned to.
	AnchorDayOfWeek *int `json:"anchor_day_of_week,omitempty"`
	// NextRunAt is the unix timestamp of the next scheduled execution.
	NextRunAt int64 `json:"next_run_at"`
	// ScatterOffset is a permanent random value (0.0-1.0) for thundering herd prevention.
	ScatterOffset float64 `json:"scatter_offset"`
	// LockedBy is the worker ID holding the processing lock, or empty if unlocked.
	LockedBy string `json:"locked_by"`
	// LockedAt is the unix timestamp of when the lock was acquired, or 0 if unlocked.
	LockedAt int64 `json:"locked_at,omitempty"`
	// LastRunAt is the unix timestamp of the last successful execution, or 0 if never run.
	LastRunAt int64 `json:"last_run_at,omitempty"`
	// ActorID is the user ID of the actor for job creation (from the config pusher).
	ActorID int64 `json:"actor_id"`
	// ActorLogin is the login of the actor for job creation.
	ActorLogin string `json:"actor_login"`
	// RepoID is the repository ID.
	RepoID int64 `json:"repo_id"`
	// RepoOwnerID is the repository owner's ID.
	RepoOwnerID int64 `json:"repo_owner_id"`
	// RepoOwnerLogin is the repository owner's login.
	RepoOwnerLogin string `json:"repo_owner_login"`
	// RepoName is the repository name.
	RepoName string `json:"repo_name"`
	// TreeOID is the commit SHA of the agent config file.
	TreeOID string `json:"tree_oid"`
	// CreatedAt is the unix timestamp of first registration.
	CreatedAt int64 `json:"created_at"`
	// UpdatedAt is the Cosmos _ts field.
	UpdatedAt int64 `json:"_ts,omitempty"`
	// LastEventUpdatedAt is the lifecycle event's UpdatedAt (UnixMicro) for
	// the version applied to this record; 0 for legacy agentsync writers.
	LastEventUpdatedAt int64 `json:"last_event_updated_at,omitempty"`
	// ETag is the CosmosDB ETag for optimistic concurrency control.
	ETag *azcore.ETag `json:"_etag,omitempty"`
}

// Schedule returns a Schedule value derived from this record.
func (t *IntervalTriggerRecord) Schedule() Schedule {
	return Schedule{
		IntervalType:    t.IntervalType,
		AnchorHourUTC:   t.AnchorHourUTC,
		AnchorDayOfWeek: t.AnchorDayOfWeek,
	}
}

// TriggerKey returns the unique identity key for this trigger (agent_id + interval_type).
func (t *IntervalTriggerRecord) TriggerKey() string {
	return t.AgentID + ":" + t.IntervalType
}

// SetTimestamps sets CreatedAt (if unset) to the current time.
// UpdatedAt (_ts) is intentionally left unset — Cosmos manages this server-side.
func (t *IntervalTriggerRecord) SetTimestamps() {
	if t.CreatedAt == 0 {
		t.CreatedAt = time.Now().Unix()
	}
}

// IntervalTriggerPatch contains optional fields for partial updates to an IntervalTriggerRecord.
// Only non-nil fields are applied via CosmosDB PatchItem.
type IntervalTriggerPatch struct {
	// Scheduler-owned fields (lock and schedule).
	LockedBy  *string `json:"locked_by,omitempty"`
	LockedAt  *int64  `json:"locked_at,omitempty"`
	NextRunAt *int64  `json:"next_run_at,omitempty"`
	LastRunAt *int64  `json:"last_run_at,omitempty"`
	// Sync-owned fields (config metadata).
	IntervalType       *string `json:"interval_type,omitempty"`
	AnchorHourUTC      *int    `json:"anchor_hour_utc,omitempty"`
	AnchorDayOfWeek    *int    `json:"anchor_day_of_week,omitempty"`
	ActorID            *int64  `json:"actor_id,omitempty"`
	ActorLogin         *string `json:"actor_login,omitempty"`
	TreeOID            *string `json:"tree_oid,omitempty"`
	LastEventUpdatedAt *int64  `json:"last_event_updated_at,omitempty"`
	// ETag for optimistic concurrency (not serialized to JSON).
	ETag *azcore.ETag `json:"-"`
}
