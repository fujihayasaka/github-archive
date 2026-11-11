package standardevents

import (
	"context"
	"strconv"
	"time"

	standardpb "github.com/github/hydro-schemas-go/hydro/schemas/analytics_pipelines/v0"
	"github.com/github/sweagentd/internal/jobs"
)

// ModelCallParams contains the model call telemetry data needed to generate
// a StandardEvent. This decouples the generator from the agentcallback types.
type ModelCallParams struct {
	Model            string
	CompletionTokens int64
	PromptTokens     int64
	TotalTokens      int64
	DurationMs       int64
	ToolCallsCount   int64
	OccurredAt       time.Time
	ProgressKind     string
	Error            string
	StatusCode       int64
	APIID            string
	RequestID        string
}

// ModelCallStandardEventGenerator generates StandardEvent messages for model call events.
type ModelCallStandardEventGenerator struct{}

// GenerateModelCallStandardEvent creates a StandardEvent for a model_call event.
func (g *ModelCallStandardEventGenerator) GenerateModelCallStandardEvent(ctx context.Context, job *jobs.Job, params ModelCallParams) *standardpb.StandardEvent {
	sdkContext := assignmentContextFromContext(ctx, job)

	event := newBaseEvent(
		EventTypeModelCall,
		params.OccurredAt,
		job.ActorAnalyticsTrackingID,
		EntityTypeCopilotTrackingID,
		sdkContext,
	)

	setSessionID(event, job.ID)

	setJobMetadata(event, job)

	event.Measurements["completion_tokens_count"] = float64(params.CompletionTokens)
	event.Measurements["prompt_tokens_count"] = float64(params.PromptTokens)
	event.Measurements["total_tokens_count"] = float64(params.TotalTokens)
	event.Measurements["duration_ms"] = float64(params.DurationMs)
	event.Measurements["tool_calls_count"] = float64(params.ToolCallsCount)

	event.Metadata["progress_kind"] = params.ProgressKind
	event.Metadata["model"] = params.Model
	if params.Error != "" {
		event.Metadata["error"] = params.Error
	}
	if params.StatusCode != 0 {
		event.Metadata["status_code"] = strconv.FormatInt(params.StatusCode, 10)
	}
	if params.APIID != "" {
		event.Metadata["api_id"] = params.APIID
	}
	if params.RequestID != "" {
		event.Metadata["request_id"] = params.RequestID
	}

	return event
}
