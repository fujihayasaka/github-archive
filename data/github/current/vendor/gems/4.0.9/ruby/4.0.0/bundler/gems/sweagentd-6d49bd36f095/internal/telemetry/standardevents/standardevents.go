// Package standardevents provides pipeline generators that convert sweagentd
// telemetry events into the unified experimentation pipeline's StandardEvent
// format. These standard events feed into the analytics/experimentation
// pipeline for scorecard evaluation, product insights, and experiment
// evaluation (e.g. the CCA auto-model A/B/C experiment).
package standardevents

import (
	"fmt"
	"time"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/timestamppb"
	"google.golang.org/protobuf/types/known/wrapperspb"
)

const (
	// OwningService is the Service Catalog slug for the coding agent.
	OwningService = "copilot-coding-agent"

	// StandardEventPrefix is the prefix for all CCA standard event types.
	StandardEventPrefix = "copilot_coding_agent"

	// EventVersion is the current version of the standard events emitted by CCA.
	EventVersion = "0.0.1"

	// HydroTopic is the Hydro topic for CCA standard events.
	HydroTopic = "copilot.sweagentd.analytics_pipelines.v0.StandardEvent"

	// Event type suffixes (combined with StandardEventPrefix to form full event types).
	eventTypeJobStarted              = "job_started"
	eventTypeJobCompleted            = "job_completed"
	eventTypeModelCall               = "model_call"
	eventTypePullRequestStateChanged = "pull_request_state_changed"

	// EntityTypeCopilotTrackingID is the entity ID type for copilot tracking IDs.
	EntityTypeCopilotTrackingID = "copilot_tracking_id"
	// EntityTypePullRequestID is the entity ID type for pull request IDs.
	EntityTypePullRequestID = "github_pull_request_id"
	// EntityTypeRepositoryID is the entity ID type for repository IDs.
	EntityTypeRepositoryID = "github_repository_id"
)

// Full event type names.
var (
	EventTypeJobStarted              = fmt.Sprintf("%s_%s", StandardEventPrefix, eventTypeJobStarted)
	EventTypeJobCompleted            = fmt.Sprintf("%s_%s", StandardEventPrefix, eventTypeJobCompleted)
	EventTypeModelCall               = fmt.Sprintf("%s_%s", StandardEventPrefix, eventTypeModelCall)
	EventTypePullRequestStateChanged = fmt.Sprintf("%s_%s", StandardEventPrefix, eventTypePullRequestStateChanged)
)

// newBaseEvent creates a StandardEvent with required fields populated.
func newBaseEvent(
	eventType string,
	occurredAt time.Time,
	primaryEntityID string,
	primaryEntityIDType string,
	primaryAssignmentContext string,
) *standardpb.StandardEvent {
	return &standardpb.StandardEvent{
		EventType:                eventType,
		OwningService:            OwningService,
		OccurredAt:               timestamppb.New(occurredAt),
		DeduplicationId:          uuid.NewString(),
		EventVersion:             EventVersion,
		PrimaryEntityId:          primaryEntityID,
		PrimaryEntityIdType:      primaryEntityIDType,
		PrimaryAssignmentContext: primaryAssignmentContext,
		Measurements:             make(map[string]float64),
		Conditions:               make(map[string]bool),
		Metadata:                 make(map[string]string),
	}
}

// setSessionID sets the session ID on a StandardEvent.
func setSessionID(event *standardpb.StandardEvent, sessionID string) {
	if sessionID != "" {
		event.SessionId = wrapperspb.String(sessionID)
	}
}

// setSecondaryEntity sets the secondary entity fields on a StandardEvent.
func setSecondaryEntity(event *standardpb.StandardEvent, entityID, entityIDType, assignmentContext string) {
	if entityID != "" {
		event.SecondaryEntityId = wrapperspb.String(entityID)
		event.SecondaryEntityIdType = wrapperspb.String(entityIDType)
	}
	if assignmentContext != "" {
		event.SecondaryAssignmentContext = wrapperspb.String(assignmentContext)
	}
}

// The following optional StandardEvent fields from the schema are not yet used:
//   - ActivityCorrelationId: domain-specific activity correlation identifier
//   - BackendActivityPair: struct for joining a backend event with a client-side event
