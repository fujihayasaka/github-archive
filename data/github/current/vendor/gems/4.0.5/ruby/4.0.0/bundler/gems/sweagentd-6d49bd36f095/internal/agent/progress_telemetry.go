package agent

import (
	"context"
	"encoding/json"
	"time"

	sweagentv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0"
	sweagentEntitiesv0 "github.com/github/hydro-schemas-go/hydro/schemas/sweagentd/v0/entities"
	"github.com/github/sweagentd/internal/agent/sessionsv2"
	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/progress"
	"github.com/github/sweagentd/internal/telemetry"
	"github.com/github/sweagentd/internal/telemetry/standardevents"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// sessionsV2TelemetryEvent is a minimal struct for extracting telemetry-relevant
// fields from sessions-v2 event content. It captures the union of fields across
// message, response, tool_execution, and model_call_failure event kinds.
type sessionsV2TelemetryEvent struct {
	Kind      string `json:"kind"`
	CallID    string `json:"callId,omitempty"`
	ModelCall struct {
		APIID     string `json:"api_id,omitempty"`
		Model     string `json:"model,omitempty"`
		RequestID string `json:"request_id,omitempty"`
		Status    int64  `json:"status,omitempty"`
		Error     string `json:"error,omitempty"`
	} `json:"modelCall,omitzero"`
	ModelCallDurationMs int64  `json:"modelCallDurationMs,omitempty"`
	RequestMessages     string `json:"requestMessages,omitempty"`
	Message             struct {
		Role string `json:"role,omitempty"`
	} `json:"message,omitzero"`
	OriginalCall *struct {
		CallID string `json:"callId,omitempty"`
	} `json:"originalCall,omitempty"`
}

// modelCallIdentifier returns the best available identifier for the model call
// associated with a sessions-v2 event, falling back through ModelCall.APIID,
// top-level CallID, and OriginalCall.CallID. Returns an empty string if none
// are populated.
func (e *sessionsV2TelemetryEvent) modelCallIdentifier() string {
	switch {
	case e.ModelCall.APIID != "":
		return e.ModelCall.APIID
	case e.CallID != "":
		return e.CallID
	case e.OriginalCall != nil && e.OriginalCall.CallID != "":
		return e.OriginalCall.CallID
	default:
		return ""
	}
}

// sessionsV2ProgressItem pairs a progress item with its pre-marshaled JSON
// content to avoid redundant marshaling.
type sessionsV2ProgressItem struct {
	progress    *progress.Progress
	contentJSON []byte
}

// sessionsV2TelemetryPublisher defines the interface for restricted telemetry
// checks and standard event publication, matching the telemetry.TelemetryPublisher
// methods used by the legacy callback handler.
type sessionsV2TelemetryPublisher interface {
	ShouldPublishRestrictedTelemetry(ctx context.Context, actorID int64) bool
	PublishModelCallStandardEvent(ctx context.Context, job *jobs.Job, params standardevents.ModelCallParams)
}

// publishSessionsV2Telemetry publishes Hydro telemetry events for sessions-v2
// progress items. This mirrors the telemetry emitted by the legacy callback
// handler (handleProgress in agentcallback/handle_progress.go).
//
// For every sessions-v2 item: publishes a JobProgress Hydro event.
// For model_call_failure items: also publishes ModelCall, RestrictedModelCall,
// and ModelCall StandardEvent.
func (s *Service) publishSessionsV2Telemetry(ctx context.Context, job *jobs.Job, items []sessionsV2ProgressItem) {
	telPub := telemetry.NewTelemetryPublisher(s.obsv, s.ghtwirp, s.ff)
	logger := s.obsv.LoggerWithTelemetry(ctx)

	for _, item := range items {
		var event sessionsV2TelemetryEvent
		err := json.Unmarshal(item.contentJSON, &event)
		if err != nil {
			logger.WithError(err).Error("failed to parse sessions-v2 content for telemetry")
			continue
		}

		s.publishJobProgressForSessionsV2(ctx, job, item.progress, &event)

		if item.progress.Kind == sessionsv2.KindModelCallFailure {
			s.publishModelCallTelemetryForSessionsV2(ctx, telPub, job, item.progress, &event)
		}
	}
}

// publishJobProgressForSessionsV2 builds and publishes a JobProgress Hydro event
// for a sessions-v2 progress item. This mirrors publishProgressTelemetry in
// agentcallback/telemetry.go.
func (s *Service) publishJobProgressForSessionsV2(ctx context.Context, job *jobs.Job, p *progress.Progress, event *sessionsV2TelemetryEvent) {
	progressKind := p.Kind

	jobProgress := &sweagentv0.JobProgress{
		Job:          telemetry.ToJob(job),
		CreatedAt:    timestamppb.New(time.Unix(p.CreatedAt, 0)),
		Kind:         sweagentEntitiesv0.JobUpdateKind_PROGRESS,
		ProgressKind: &progressKind,
	}

	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		jobProgress.ExpAssignmentContext = job.Experiments.AssignmentContext
	}

	if event.Message.Role != "" {
		jobProgress.Role = &event.Message.Role
	}

	jobProgress.ModelCallId = event.modelCallIdentifier()

	err := s.obsv.HydroPbl.Publish(jobProgress)
	if err != nil {
		s.obsv.LoggerWithTelemetry(ctx).WithError(err).Error("failed to publish job_progress event for sessions-v2")
	}
}

// publishModelCallTelemetryForSessionsV2 publishes ModelCall, RestrictedModelCall Hydro events,
// and a ModelCall StandardEvent for a sessions-v2 model_call_failure event.
// This mirrors the model_call_failure handling in publishTelemetry (agentcallback/telemetry.go).
func (s *Service) publishModelCallTelemetryForSessionsV2(ctx context.Context, telPub sessionsV2TelemetryPublisher, job *jobs.Job, p *progress.Progress, event *sessionsV2TelemetryEvent) {
	logger := s.obsv.LoggerWithTelemetry(ctx)
	createdAt := timestamppb.New(time.Unix(p.CreatedAt, 0))

	shouldPublishRestricted := telPub.ShouldPublishRestrictedTelemetry(ctx, job.ActorID)

	modelCallID := event.modelCallIdentifier()

	// Publish ModelCall Hydro event.
	modelCallEvent := &sweagentv0.ModelCall{
		JobId:        job.ID,
		AssignmentId: job.AssignmentID,
		CreatedAt:    createdAt,
		ApiCreatedAt: createdAt,
		DurationMs:   event.ModelCallDurationMs,
		Model:        event.ModelCall.Model,
		RequestId:    event.ModelCall.RequestID,
		Status:       event.ModelCall.Status,
	}
	if modelCallID != "" {
		modelCallEvent.ApiId = modelCallID
	}
	if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
		modelCallEvent.ExpAssignmentContext = job.Experiments.AssignmentContext
	}

	err := s.obsv.HydroPbl.Publish(modelCallEvent)
	if err != nil {
		logger.WithError(err).Error("failed to publish model_call event for sessions-v2")
	}

	// Publish RestrictedModelCall Hydro event (if allowed).
	if shouldPublishRestricted {
		restrictedEvent := &sweagentv0.RestrictedModelCall{
			JobId:        job.ID,
			AssignmentId: job.AssignmentID,
			CreatedAt:    createdAt,
			ApiCreatedAt: createdAt,
			DurationMs:   event.ModelCallDurationMs,
			Model:        event.ModelCall.Model,
			RequestId:    event.ModelCall.RequestID,
			Status:       event.ModelCall.Status,
			Error:        event.ModelCall.Error,
			Messages:     event.RequestMessages,
		}
		if modelCallID != "" {
			restrictedEvent.ApiId = modelCallID
		}
		if job.Experiments != nil && job.Experiments.AssignmentContext != "" {
			restrictedEvent.ExpAssignmentContext = job.Experiments.AssignmentContext
		}

		err := s.obsv.HydroPbl.Publish(restrictedEvent)
		if err != nil {
			logger.WithError(err).Error("failed to publish restricted model_call event for sessions-v2")
		}
	}

	// Publish ModelCall StandardEvent.
	params := standardevents.ModelCallParams{
		DurationMs:   event.ModelCallDurationMs,
		OccurredAt:   time.Unix(p.CreatedAt, 0),
		ProgressKind: p.Kind,
		StatusCode:   event.ModelCall.Status,
		RequestID:    event.ModelCall.RequestID,
		Model:        event.ModelCall.Model,
		APIID:        modelCallID,
	}
	if shouldPublishRestricted {
		params.Error = event.ModelCall.Error
	}

	telPub.PublishModelCallStandardEvent(ctx, job, params)
}
