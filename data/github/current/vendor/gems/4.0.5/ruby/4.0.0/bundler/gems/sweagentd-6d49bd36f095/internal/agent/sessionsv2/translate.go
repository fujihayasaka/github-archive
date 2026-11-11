// Package sessionsv2 translates sessions-v2 progress payloads.
package sessionsv2

import (
	"encoding/json"
	"time"

	"github.com/github/sweagentd/internal/goerrors"
	"github.com/google/uuid"
)

// Namespace is the progress namespace that triggers server-side translation.
const Namespace = "sessions-v2"

// Event kinds that engines can send.
const (
	KindMessage          = "message"
	KindToolExecution    = "tool_execution"
	KindResponse         = "response"
	KindModelCallFailure = "model_call_failure"
	KindHistoryTruncated = "history_truncated"

	// KindReportProgress triggers a PR title/description update (side-effect kind).
	KindReportProgress = "report_progress"
	// KindCommentReply triggers a reply to a PR comment (side-effect kind).
	KindCommentReply = "comment_reply"
	// KindPRSummary triggers a final PR title/description update (side-effect kind).
	// Sent by engines after the agentic loop to provide a polished PR summary.
	KindPRSummary = "pr_summary"
)

// engineEvent is the top-level shape used to peek at the event kind.
type engineEvent struct {
	Kind string `json:"kind"`
}

// assistantMessageEvent is the payload for kind=message, role=assistant.
type assistantMessageEvent struct {
	CallID    string         `json:"callId,omitempty"`
	AgentID   string         `json:"agentId,omitempty"`
	ModelCall *modelCallInfo `json:"modelCall,omitempty"`
	Message   struct {
		Role      string     `json:"role"`
		Content   *string    `json:"content,omitempty"`
		ToolCalls []toolCall `json:"tool_calls,omitempty"`
	} `json:"message"`
}

// toolMessageEvent is the payload for kind=message, role=tool.
type toolMessageEvent struct {
	AgentID string `json:"agentId,omitempty"`
	Message struct {
		ToolCallID string `json:"tool_call_id"`
		Content    string `json:"content"`
	} `json:"message"`
}

// userMessageEvent is the payload for kind=message, role=user.
// Source lives at the top level of the event, not inside message.
type userMessageEvent struct {
	AgentID string `json:"agentId,omitempty"`
	Source  string `json:"source,omitempty"`
	Message struct {
		Content string `json:"content"`
	} `json:"message"`
}

// toolExecutionEvent is the payload for kind=tool_execution.
// The originalCall field is populated by the SDK with context from
// the assistant message that requested this tool call.
type toolExecutionEvent struct {
	AgentID    string `json:"agentId,omitempty"`
	CallID     string `json:"callId,omitempty"`
	ToolCallID string `json:"toolCallId"`
	ToolName   string `json:"toolName,omitempty"`
	ToolResult struct {
		TextResultForLlm string `json:"textResultForLlm"`
		ResultType       string `json:"resultType"`
		// SessionLog is the UI-facing detailed result (e.g. unified diff).
		// When non-empty it is preferred over TextResultForLlm for delta.content.
		SessionLog string `json:"sessionLog,omitempty"`
		// DetailedContent is an alias for SessionLog used by some engines.
		// Used only when SessionLog is empty (sessionLog > detailedContent > textResultForLlm).
		DetailedContent string `json:"detailedContent,omitempty"`
	} `json:"toolResult"`
	OriginalCall *originalCallContext `json:"originalCall,omitempty"`
}

type originalCallContext struct {
	CallID   string   `json:"callId"`
	Model    string   `json:"model"`
	ToolCall toolCall `json:"toolCall"`
}

// responseEvent is the payload for kind=response.
type responseEvent struct {
	CallID    string         `json:"callId,omitempty"`
	ModelCall *modelCallInfo `json:"modelCall,omitempty"`
	Response  struct {
		Content string `json:"content"`
	} `json:"response"`
}

type modelCallInfo struct {
	Model string `json:"model,omitempty"`
}

type toolCall struct {
	ID       string       `json:"id"`
	Type     string       `json:"type"`
	Index    int          `json:"index,omitempty"`
	Function toolFunction `json:"function"`
}

type toolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type sessionLogChunk struct {
	ID      string             `json:"id"`
	Created int64              `json:"created"`
	Model   string             `json:"model"`
	Object  string             `json:"object"`
	AgentID string             `json:"agentId,omitempty"`
	Choices []sessionLogChoice `json:"choices"`
}

type sessionLogChoice struct {
	Index        int             `json:"index"`
	Delta        sessionLogDelta `json:"delta"`
	FinishReason *string         `json:"finish_reason"`
}

type sessionLogDelta struct {
	Content   *string    `json:"content,omitempty"`
	Role      string     `json:"role,omitempty"`
	ToolCalls []toolCall `json:"tool_calls,omitempty"`
}

type sessionLogToolMessage struct {
	Role       string `json:"role"`
	ToolCallID string `json:"tool_call_id"`
	Content    string `json:"content"`
	AgentID    string `json:"agentId,omitempty"`
}

type sessionLogUserMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
	Source  string `json:"source,omitempty"`
	AgentID string `json:"agentId,omitempty"`
}

// TranslateResult holds the output of a translation.
type TranslateResult struct {
	// SessionLog is the translated content. For Kind "log" this is
	// session-legacy format; for Kind "progress" it is the original
	// sessions-v2 payload passed through unchanged.
	SessionLog json.RawMessage
	// Kind is the progress kind to use: "log" for renderable events,
	// "progress" for telemetry-only events.
	Kind string
}

// TranslateWithKind converts a sessions-v2 progress item into the
// session-legacy format. progressKind is used only as a fallback for known
// telemetry events whose envelope kind is not repeated inside content.
func TranslateWithKind(progressKind string, content json.RawMessage) (*TranslateResult, error) {
	var base engineEvent
	err := json.Unmarshal(content, &base)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse event: %w", err)
	}
	if base.Kind == "" && isTelemetryPassthroughKind(progressKind) {
		base.Kind = progressKind
	}

	switch base.Kind {
	case KindMessage:
		return translateMessage(content)
	case KindToolExecution:
		return translateToolExecution(content)
	case KindResponse:
		return translateResponse(content)
	case KindModelCallFailure, KindHistoryTruncated, KindReportProgress, KindCommentReply, KindPRSummary:
		// Telemetry and side-effect kinds pass through as-is.
		// Side-effect kinds trigger platform operations separately
		// (PR update, comment reply) via dispatchSideEffects.
		return &TranslateResult{SessionLog: content, Kind: "progress"}, nil
	default:
		return nil, goerrors.Errorf("unknown event kind: %q", base.Kind)
	}
}

func isTelemetryPassthroughKind(kind string) bool {
	switch kind {
	case KindModelCallFailure, KindHistoryTruncated:
		return true
	default:
		return false
	}
}

// IsSideEffectKind reports whether kind is handled through dispatchSideEffects
// rather than the session log stream.
func IsSideEffectKind(kind string) bool {
	switch kind {
	case KindReportProgress, KindCommentReply, KindPRSummary:
		return true
	default:
		return false
	}
}

func translateMessage(content json.RawMessage) (*TranslateResult, error) {
	var peek struct {
		Message struct {
			Role string `json:"role"`
		} `json:"message"`
	}
	err := json.Unmarshal(content, &peek)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse message role: %w", err)
	}

	switch peek.Message.Role {
	case "assistant":
		return translateAssistantMessage(content)
	case "tool":
		return translateToolMessage(content)
	case "user":
		return translateUserMessage(content)
	default:
		return nil, goerrors.Errorf("unknown message role: %q", peek.Message.Role)
	}
}

func translateAssistantMessage(content json.RawMessage) (*TranslateResult, error) {
	var event assistantMessageEvent
	err := json.Unmarshal(content, &event)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse assistant message: %w", err)
	}

	callID := event.CallID
	if callID == "" {
		callID = uuid.NewString()
	}

	model := "unknown"
	if event.ModelCall != nil && event.ModelCall.Model != "" {
		model = event.ModelCall.Model
	}

	delta := sessionLogDelta{Role: "assistant"}
	if event.Message.Content != nil {
		delta.Content = event.Message.Content
	}

	var finishReason *string
	if len(event.Message.ToolCalls) > 0 {
		toolCallDeltas := make([]toolCall, 0, len(event.Message.ToolCalls))
		for i, tc := range event.Message.ToolCalls {
			toolCallDeltas = append(toolCallDeltas, toolCall{
				ID:    tc.ID,
				Type:  tc.Type,
				Index: i,
				Function: toolFunction{
					Name:      tc.Function.Name,
					Arguments: tc.Function.Arguments,
				},
			})
		}
		delta.ToolCalls = toolCallDeltas
		finishReason = stringPtr("tool_calls")
	}

	chunk := sessionLogChunk{
		ID:      callID,
		Created: time.Now().Unix(),
		Model:   model,
		Object:  "chat.completion.chunk",
		AgentID: event.AgentID,
		Choices: []sessionLogChoice{
			{
				Index:        0,
				Delta:        delta,
				FinishReason: finishReason,
			},
		},
	}

	chunkJSON, err := json.Marshal(chunk)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal assistant chunk: %w", err)
	}

	// When the assistant message carries a `permission_request` tool_call, the
	// runtime is asking the user to approve/deny a non-readOnly MCP tool call
	// and is about to block on the response. Emit Kind="permission_request"
	// instead of "log" so Mission Control's JobProgressConsumer can transition
	// the session into SessionStateWaitingForUser. The SessionLog content is
	// unchanged — the UI still renders the prompt from the SSE log entry.
	for _, tc := range event.Message.ToolCalls {
		if tc.Function.Name == "permission_request" {
			return &TranslateResult{SessionLog: chunkJSON, Kind: "permission_request"}, nil
		}
	}

	return &TranslateResult{SessionLog: chunkJSON, Kind: "log"}, nil
}

func translateToolMessage(content json.RawMessage) (*TranslateResult, error) {
	var event toolMessageEvent
	err := json.Unmarshal(content, &event)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse tool message: %w", err)
	}

	toolMsg := sessionLogToolMessage{
		Role:       "tool",
		ToolCallID: event.Message.ToolCallID,
		Content:    event.Message.Content,
		AgentID:    event.AgentID,
	}

	msgJSON, err := json.Marshal(toolMsg)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal tool message: %w", err)
	}

	return &TranslateResult{SessionLog: msgJSON, Kind: "log"}, nil
}

func translateUserMessage(content json.RawMessage) (*TranslateResult, error) {
	var event userMessageEvent
	err := json.Unmarshal(content, &event)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse user message: %w", err)
	}

	userMsg := sessionLogUserMessage{
		Role:    "user",
		Content: event.Message.Content,
		Source:  event.Source,
		AgentID: event.AgentID,
	}

	msgJSON, err := json.Marshal(userMsg)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal user message: %w", err)
	}

	return &TranslateResult{SessionLog: msgJSON, Kind: "log"}, nil
}

func translateToolExecution(content json.RawMessage) (*TranslateResult, error) {
	var event toolExecutionEvent
	err := json.Unmarshal(content, &event)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse tool execution: %w", err)
	}

	// Resolve call context. The SDK may provide originalCall (legacy) or
	// top-level callId/toolName fields (engine-sdk). When neither is
	// present the event is telemetry-only.
	callID := ""
	model := "unknown"
	var tc toolCall

	switch {
	case event.OriginalCall != nil:
		callID = event.OriginalCall.CallID
		model = event.OriginalCall.Model
		tc = event.OriginalCall.ToolCall
		if tc.ID == "" {
			tc.ID = event.ToolCallID
		}
	case event.CallID != "":
		// engine-sdk createToolExecutionEvent puts callId/toolName at the top level.
		callID = event.CallID
		tc = toolCall{
			ID:   event.ToolCallID,
			Type: "function",
			Function: toolFunction{
				Name: event.ToolName,
			},
		}
	default:
		// No call context at all - pass through as telemetry.
		return &TranslateResult{SessionLog: content, Kind: "progress"}, nil
	}

	// Prefer the UI-facing detailed result for rendered session logs.
	// sessionLog > detailedContent > textResultForLlm.
	resultText := event.ToolResult.TextResultForLlm
	if event.ToolResult.SessionLog != "" {
		resultText = event.ToolResult.SessionLog
	} else if event.ToolResult.DetailedContent != "" {
		resultText = event.ToolResult.DetailedContent
	}
	if event.ToolResult.ResultType != "success" {
		resultText = "<error>" + resultText + "</error>"
	}

	chunk := sessionLogChunk{
		ID:      callID,
		Created: time.Now().Unix(),
		Model:   model,
		Object:  "chat.completion.chunk",
		AgentID: event.AgentID,
		Choices: []sessionLogChoice{
			{
				Index:        0,
				FinishReason: stringPtr("tool_calls"),
				Delta: sessionLogDelta{
					Content: stringPtr(resultText),
					Role:    "assistant",
					ToolCalls: []toolCall{
						{
							ID:    tc.ID,
							Type:  tc.Type,
							Index: 0,
							Function: toolFunction{
								Name:      tc.Function.Name,
								Arguments: tc.Function.Arguments,
							},
						},
					},
				},
			},
		},
	}

	chunkJSON, err := json.Marshal(chunk)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal tool execution chunk: %w", err)
	}

	return &TranslateResult{SessionLog: chunkJSON, Kind: "log"}, nil
}

func translateResponse(content json.RawMessage) (*TranslateResult, error) {
	var event responseEvent
	err := json.Unmarshal(content, &event)
	if err != nil {
		return nil, goerrors.Errorf("failed to parse response: %w", err)
	}

	callID := event.CallID
	if callID == "" {
		callID = uuid.NewString()
	}

	model := "unknown"
	if event.ModelCall != nil && event.ModelCall.Model != "" {
		model = event.ModelCall.Model
	}

	chunk := sessionLogChunk{
		ID:      callID,
		Created: time.Now().Unix(),
		Model:   model,
		Object:  "chat.completion.chunk",
		Choices: []sessionLogChoice{
			{
				Index:        0,
				FinishReason: stringPtr("stop"),
				Delta: sessionLogDelta{
					Content: stringPtr(event.Response.Content),
					Role:    "assistant",
				},
			},
		},
	}

	chunkJSON, err := json.Marshal(chunk)
	if err != nil {
		return nil, goerrors.Errorf("failed to marshal response chunk: %w", err)
	}

	return &TranslateResult{SessionLog: chunkJSON, Kind: "log"}, nil
}

func stringPtr(s string) *string {
	return &s
}
