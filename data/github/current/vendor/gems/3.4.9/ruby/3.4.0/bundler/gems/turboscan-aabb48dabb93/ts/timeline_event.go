package ts

import (
	"context"

	"github.com/SamuelTissot/sqltime"
	"github.com/github/turboscan/ts/auditlog"
	"github.com/pkg/errors"
)

type AlertEventHandler interface {
	NewAlertEvent(ctx context.Context, la *LogicalAlert, event *TimelineEvent) error
	NewAuditEvents(ctx context.Context, batch AuditEntryBatch, auditLogContext auditlog.AuditLogContext) error
	Flush() error
}

var (
	ErrTimeLineEventsNotFound = errors.New("timeline events not found")
)

type TimelineEventID uint64

// A TimelineEvent represents an event affecting the alert state
type TimelineEvent struct {
	BaseModel
	ID             TimelineEventID
	RepositoryID   RepositoryEID
	LogicalAlertID LogicalAlertID
	EventType      TimelineEventType
	EventTimestamp sqltime.Time
	CommitOid      Sha             // required for AlertCreated, AlertAppearedInBranch, AlertReappeared, AlertFixed
	Ref            string          // required for AlertCreated, AlertAppearedInBranch, AlertReappeared, AlertFixed
	UserID         *UserEID        // required for AlertResolvedByUser, AlertReopenedByUser
	Resolution     AlertResolution // defaults to 0, non-zero values for AlertResolvedByUser
	ResolutionNote Note            // defaults to null, non-null values for AlertResolvedByUser
	FilePath       string          // required for AlertCreated, AlertAppearedInBranch, AlertReappeared
	StartLine      uint32          // required for AlertCreated, AlertAppearedInBranch, AlertReappeared
	ToolVersionID  ToolVersionID   // required for AlertCreated, AlertAppearedInBranch, AlertReappeared, AlertFixed
	AnalysisID     AnalysisID      // required for AlertCreated, AlertAppearedInBranch, AlertReappeared, AlertFixed
	Environment    AnalysisEnv     // JSON
	WorkflowRunID  WorkflowRunEID
	Category       string `gorm:"-"`

	// Associations
	ToolVersion_ *ToolVersion `gorm:"foreignKey:ToolVersionID"` // TODO: Rename this to a sane `ToolVersionID` once we drop the underlying column
	Analysis     *Analysis    `verify:"ignore"`

	// Non-persisted fields
	NonUnique bool `gorm:"-"` // The alert already existed, but was detected in a new branch. These events are not written to the database, nor are webhooks emitted, but they do trigger audit log events.
}

// TimelineEventFilter defines the filtering conditions to apply to an TimelineEvent query.
type TimelineEventFilter struct {
	RepositoryID   RepositoryEID
	LogicalAlertID LogicalAlertID
	AnalysisID     AnalysisID
	EventTypes     []TimelineEventType
}

// TimelineEventType describes the possible types of events that can
// occur in the timeline.
type TimelineEventType uint8

// If adding new constants here, be sure to update TimelineEventType in results.proto
// and results_resolver::serializeTimelineEventType, as well as the String() and
// isValid() functions below
const (
	TimelineEventTypeUnknown                   TimelineEventType = 0
	TimelineEventTypeAlertAppearedInBranch     TimelineEventType = 10
	TimelineEventTypeAlertClosedBecameFixed    TimelineEventType = 30
	TimelineEventTypeAlertClosedBecameOutdated TimelineEventType = 35
	TimelineEventTypeAlertResolvedByUser       TimelineEventType = 40
	TimelineEventTypeAlertCreated              TimelineEventType = 60
	TimelineEventTypeAlertReappeared           TimelineEventType = 70
	TimelineEventTypeAlertReopenedByUser       TimelineEventType = 90
	TimelineEventTypeAlertDeletedByUser        TimelineEventType = 100
)

func (t TimelineEventType) String() string {
	switch t {
	case TimelineEventTypeUnknown:
		return "Unknown"
	case TimelineEventTypeAlertAppearedInBranch:
		return "Alert appeared in ref"
	case TimelineEventTypeAlertClosedBecameFixed:
		return "Alert closed: became fixed"
	case TimelineEventTypeAlertClosedBecameOutdated:
		return "Alert closed: became outdated"
	case TimelineEventTypeAlertResolvedByUser:
		return "Alert closed: by user"
	case TimelineEventTypeAlertCreated:
		return "Alert created"
	case TimelineEventTypeAlertReappeared:
		return "Alert reappeared"
	case TimelineEventTypeAlertReopenedByUser:
		return "Alert re-opened by user"
	case TimelineEventTypeAlertDeletedByUser:
		return "Alert deleted by user"
	default:
		panic("Invalid TimelineEventType value")
	}
}

func (t TimelineEventType) IsValid() bool {
	switch t {
	case
		TimelineEventTypeUnknown,
		TimelineEventTypeAlertAppearedInBranch,
		TimelineEventTypeAlertClosedBecameFixed,
		TimelineEventTypeAlertClosedBecameOutdated,
		TimelineEventTypeAlertResolvedByUser,
		TimelineEventTypeAlertCreated,
		TimelineEventTypeAlertReappeared,
		TimelineEventTypeAlertReopenedByUser,
		TimelineEventTypeAlertDeletedByUser:
		return true
	default:
		return false
	}
}
