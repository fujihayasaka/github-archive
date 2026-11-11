package agentcallback

import (
	"cmp"
	"context"
	"encoding/json"
	"net/http"
	"slices"
	"time"

	"github.com/github/sweagentd/internal/jobs"
	"github.com/github/sweagentd/internal/jobs/command"
	db "github.com/github/sweagentd/internal/jobs/store"
	"github.com/github/sweagentd/internal/telemetry"
)

// ProgressJobEvent represents job progress telemetry data structure
type ProgressJobEvent struct {
	Kind string `json:"kind"`
	// Set for ModelCallFailureEvent and ModelCallSuccessEvent (kind: "model_call_failure" | "model_call_success")
	ModelCall ModelCall `json:"modelCall"`
	// Set for MessageEvent and its subtypes (kind: "message")
	Message Message `json:"message"`
	// Set for ResponseEvent (kind: "response")
	Response Response `json:"response"`
	// Set for ModelCallSuccessEvent (kind: "model_call_success")
	ResponseChunk ChatCompletionChunk `json:"responseChunk"`
	// Potentially set for any event kind
	Telemetry Telemetry `json:"telemetry"`
	// Set for ModelCallFailureEvent and ModelCallSuccessEvent (kind: "model_call_failure" | "model_call_success")
	ModelCallDurationMs int64 `json:"modelCallDurationMs"`
	// Set for ModelCallFailureEvent and ModelCallSuccessEvent (kind: "model_call_failure" | "model_call_success")
	RequestMessages string `json:"requestMessages"`
	// Set for SessionLoggingDisabledEvent (kind: "session_logging_disabled")
	Reason string `json:"reason"`
	// Set for SessionLoggingDisabledEvent (kind: "session_logging_disabled")
	RequestID string `json:"requestId"`
	// Set for SessionLoggingDisabledEvent (kind: "session_logging_disabled")
	ResponseBody string `json:"responseBody"`
	// Set for SessionLoggingDisabledEvent (kind: "session_logging_disabled")
	StatusCode int64 `json:"statusCode"`
}

// ModelCall represents API call information for telemetry
type ModelCall struct {
	APIID     string `json:"api_id"`
	Model     string `json:"model"`
	RequestID string `json:"request_id"`
	Status    int64  `json:"status"`
	Error     string `json:"error"`
}

// GetRole returns role if available, there should only be one role
func (progress *ProgressJobEvent) GetRole() (string, bool) {
	if progress.Message.Role != "" {
		return progress.Message.Role, true
	}

	if progress.Response.Role != "" {
		return progress.Response.Role, true
	}

	if len(progress.ResponseChunk.Choices) > 0 {
		for _, choice := range progress.ResponseChunk.Choices {
			if choice.Delta.Role != "" {
				return choice.Delta.Role, true
			}
		}
	}

	return "", false
}

// Message represents a message in a job event which can be either a complex object or a simple string
type Message struct {
	// Fields for when message is an object
	Role string `json:"role,omitempty"`
	// uncommenting might leak info into the logs, so uncommenting requires checking generateProgressJobEventTelemetry
	Content string `json:"content"`
	// Refusal    string     `json:"refusal"`
	ToolCallID string     `json:"tool_call_id,omitempty"`
	ToolCalls  []ToolCall `json:"tool_calls,omitempty"`
	// Raw message when message is a string
	StringValue string `json:"-"`
}

// UnmarshalJSON custom implementation for handling both object and string message formats
func (m *Message) UnmarshalJSON(data []byte) error {
	// First try as string
	var s string
	err := json.Unmarshal(data, &s)
	if err == nil {
		m.StringValue = s
		return nil
	}

	// If not a string, try as object
	type MessageAlias Message
	alias := &struct {
		*MessageAlias
	}{
		MessageAlias: (*MessageAlias)(m),
	}

	err = json.Unmarshal(data, alias)
	if err != nil {
		return err
	}

	return nil
}

// Response represents the response structure for telemetry
type Response struct {
	Role string `json:"role"`
	// uncommenting might leak info into the logs, so uncommenting requires checking generateProgressJobEventTelemetry
	// Content string `json:"content"`
}

// ChatCompletionChunk represents a chunk of chat completion response
type ChatCompletionChunk struct {
	ID      string   `json:"id"`
	Choices []Choice `json:"choices"`
	Created int64    `json:"created"`
	Model   string   `json:"model"`
	Object  string   `json:"object"`
	Usage   Usage    `json:"usage"`
}

// Choice represents a choice in chat completion response
type Choice struct {
	Delta        Delta  `json:"delta"`
	FinishReason string `json:"finish_reason"`
}

// Delta represents the delta portion of a choice
type Delta struct {
	Toolcalls []ToolCall `json:"tool_calls"`
	// uncommenting might leak info into the logs, so uncommenting requires checking generateProgressJobEventTelemetry
	Content string `json:"content"`
	Refusal string `json:"refusal"`
	Role    string `json:"role"`
}

// Usage represents token usage information
type Usage struct {
	CompletionTokens int64 `json:"completion_tokens"`
	PromptTokens     int64 `json:"prompt_tokens"`
	TotalTokens      int64 `json:"total_tokens"`
}

// Telemetry represents telemetry data structure
type Telemetry struct {
	Event                string             `json:"event"`
	Properties           map[string]string  `json:"properties"`
	RestrictedProperties map[string]string  `json:"restrictedProperties"`
	Metrics              map[string]float64 `json:"metrics"`
}

// ToolCall represents a tool call in telemetry data
type ToolCall struct {
	// Fields for ToolCalls in Message and ModelCallSuccess events
	ID       string           `json:"id,omitempty"`
	Type     string           `json:"type,omitempty"`
	Function FunctionToolCall `json:"function"`
	// Fields for ToolCalls in GetCompletionWithToolsTurnProperties Telemetry event
	ToolCallID string `json:"toolCallId,omitempty"`
	ToolName   string `json:"toolName,omitempty"`
}

// FunctionToolCall represents a function tool call
type FunctionToolCall struct {
	Name string `json:"name"`
	// uncommenting might leak info into the logs, so uncommenting requires checking telemetryFields
	Arguments string `json:"arguments"`
}

func (m *jobManager) handleProgress(ctx context.Context, r *http.Request, job *jobs.Job, update JobUpdate) (*JobResult, error) {
	m.obsv.LoggerWithRequestTelemetry(ctx, r).Info("processing agent callback: progress")
	update.publishProgressTelemetry(ctx, m.obsv, job)

	jobResult := &JobResult{
		Status: jobs.JobStatusRunning,
	}

	progress := ProgressJobEvent{}
	// do not fail on an unsuccessful unmarshal, as all the properties are used for telemetry only
	_ = json.Unmarshal([]byte(update.Content), &progress)

	telemetryPublisher := telemetry.NewTelemetryPublisher(m.obsv, m.ghTwirp, m.ffClient)
	progress.publishTelemetry(ctx, m.obsv, telemetryPublisher, job, update)

	if update.AcceptsUserMessages {
		pendingCommands, err := m.jobsStore.GetCommandsWithStatus(ctx, job.AssignmentID, job.ID, command.StatusPending)
		if err != nil {
			// We don't want to fail the whole progress update if we can't get commands
			m.obsv.LogAndReportError(ctx, err, "failed to get pending commands")
			return jobResult, nil
		}

		userMessages := make([]*command.Command, 0, len(pendingCommands))
		for _, cmd := range pendingCommands {
			if cmd.Type == command.TypeUserMessage {
				userMessages = append(userMessages, cmd)
			}
		}

		slices.SortFunc(userMessages, func(a, b *command.Command) int {
			return cmp.Compare(a.Timestamp(), b.Timestamp())
		})

		status := command.StatusDelivered
		now := time.Now().Unix()
		err = m.jobsStore.BatchPatchCommands(ctx, userMessages, db.CommandPatch{
			Status:      &status,
			DeliveredAt: &now,
		})
		if err != nil {
			// We don't want to fail the whole progress update if we can't update our commands
			m.obsv.LogAndReportError(ctx, err, "failed to update pending commands")
			return jobResult, nil
		}

		userMessagesResponse := make([]UserMessageResponse, 0, len(userMessages))
		for _, msg := range userMessages {
			// Since we batch updated, we need to update the command in place to ensure
			// it reflects the actual state of the command.
			msg.Status = status
			msg.DeliveredAt = now
			userMessagesResponse = append(userMessagesResponse, UserMessageResponse{
				ID:        msg.ID,
				ActorID:   msg.ActorID,
				Content:   msg.Content,
				Timestamp: msg.Timestamp(),
			})
			telemetryPublisher.PublishCommandUpdatedTelemetry(ctx, msg)
		}
		jobResult.Response = &ProgressResponse{
			UserMessages: userMessagesResponse,
		}
	}

	return jobResult, nil
}
