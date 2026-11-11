package provider

import (
	"context"
	"fmt"
	"time"

	"github.com/github/code-scanning-ai-libraries/v2/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v2/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// Finish reason constants for session logging chunks.
const (
	FinishReasonStop      = "stop"
	FinishReasonToolCalls = "tool_calls"
)

// formatError wraps an error message in <error> tags for structured session logging.
func formatError(err error) string {
	return "<error>" + err.Error() + "</error>"
}

// ToolFunction represents the metadata of a tool call.
type ToolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

// ToolCall represents a single tool call invocation.
type ToolCall struct {
	ID       string       `json:"id"`
	Index    int          `json:"index"`
	Function ToolFunction `json:"function"`
}

// Delta models the incremental delta payload in a streaming chat.completion.chunk format.
type Delta struct {
	Role      string     `json:"role,omitempty"`
	Content   string     `json:"content,omitempty"`
	ToolCalls []ToolCall `json:"tool_calls,omitempty"`
}

// Choice is a single choice in a chunk (index + finish_reason + delta).
type Choice struct {
	Index        int    `json:"index"`
	FinishReason string `json:"finish_reason,omitempty"`
	Delta        Delta  `json:"delta"`
}

// Chunk represents a chat.completion.chunk style session log.
type Chunk struct {
	ID      string             `json:"id"`
	Object  string             `json:"object"`
	Created int64              `json:"created"`
	Model   string             `json:"model"`
	Choices []Choice           `json:"choices"`
	Usage   *models.TokenUsage `json:"usage,omitempty"`
}

// BuildAssistantContentChunk is an helper which creates a simple assistant content chunk.
// Caller can use this to generate session log payloads that conform to chat.completion.chunk
// structure we emit here as per session APIs spec.
func BuildAssistantContentChunk(id, model, content, finishReason string, created int64) Chunk {
	if finishReason == "" {
		finishReason = FinishReasonStop
	}
	if created == 0 {
		created = time.Now().UnixMilli()
	}
	return Chunk{
		ID:      id,
		Object:  "chat.completion.chunk",
		Created: created,
		Model:   model,
		Choices: []Choice{{
			Index:        0,
			FinishReason: finishReason,
			Delta: Delta{
				Role:    "assistant",
				Content: content,
			},
		}},
	}
}

// Session recording context keys (private sentinel types)
type sessionRecorderKeyType struct{}

var sessionRecorderKey = sessionRecorderKeyType{}

// userMessagesRecordedKeyType is used to track if user messages have been recorded in this request lifecycle.
// Without this, user messages would be recorded multiple times during tool calling recursion.
type userMessagesRecordedKeyType struct{}

var userMessagesRecordedKey = userMessagesRecordedKeyType{}

// WithSessionRecorder stores a SessionRecorder instance in the context.
func WithSessionRecorder(ctx context.Context, recorder SessionRecorder) context.Context {
	return context.WithValue(ctx, sessionRecorderKey, recorder)
}

// getSessionRecorder retrieves the SessionRecorder from context, or nil if not set.
func getSessionRecorder(ctx context.Context) SessionRecorder {
	if v, ok := ctx.Value(sessionRecorderKey).(SessionRecorder); ok {
		return v
	}
	return nil
}

// markUserMessagesRecorded marks in context that user messages have been recorded.
// This prevents duplicate user chunks during tool calling recursion.
func markUserMessagesRecorded(ctx context.Context) context.Context {
	return context.WithValue(ctx, userMessagesRecordedKey, true)
}

// wereUserMessagesRecorded checks if user messages were already recorded in this request lifecycle.
func wereUserMessagesRecorded(ctx context.Context) bool {
	if v, ok := ctx.Value(userMessagesRecordedKey).(bool); ok {
		return v
	}
	return false
}

// hasSessionRecorder checks if a session recorder is available either from context or struct field.
func (c *CAPIClient) hasSessionRecorder(ctx context.Context) bool {
	return c.getAvailableSessionRecorder(ctx) != nil
}

// getAvailableSessionRecorder retrieves the session recorder from context with fallback to struct field.
func (c *CAPIClient) getAvailableSessionRecorder(ctx context.Context) SessionRecorder {
	recorder := getSessionRecorder(ctx)
	if recorder == nil {
		recorder = c.sessionRecorder
	}
	return recorder
}

// recordToolMessage records a tool response to the session.
// For Sessions UI compatibility, tool responses must be in chat.completion.chunk format with BOTH:
// 1. tool_calls array (repeated from the original tool call) - so UI knows which tool this response belongs to
// 2. content field (the tool output) - where UI reads the actual output from
// This matches the format Sessions UI expects: choice.delta.tool_calls[0] identifies the tool, choice.delta.content has the output.
func (c *CAPIClient) recordToolMessage(ctx context.Context, toolCall models.ToolCall, content string) {
	recorder := c.getAvailableSessionRecorder(ctx)
	if recorder == nil {
		return
	}

	// Sessions UI's LogEntryChoice component expects tool responses in chat.completion.chunk format
	// with tool_calls in delta (to identify the tool) AND content in delta (for the output).
	// Without this format, the UI won't recognize or render tool responses.
	recorder.Record(ctx, Chunk{
		ID:      fmt.Sprintf("cmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion.chunk",
		Created: time.Now().UnixMilli(),
		Model:   c.GetModelName(),
		Choices: []Choice{
			{
				Index: 0,
				Delta: Delta{
					ToolCalls: []ToolCall{
						{
							Index: 0,
							ID:    toolCall.ID,
							Function: ToolFunction{
								Name:      toolCall.Function.Name,
								Arguments: toolCall.Function.Arguments,
							},
						},
					},
					Content: content,
				},
				// No finish_reason for tool responses - this is not the assistant finishing,
				// it's a tool completing its execution. Sessions UI doesn't rely on this field
				// for tool rendering (it relies on checks delta.tool_calls and delta.content ).
				FinishReason: "",
			},
		},
	})

	enhancedctx.Logger(ctx).Info("recorded tool message", []kvp.Field{
		kvp.String("tool_call_id", toolCall.ID),
		kvp.String("tool_name", toolCall.Function.Name),
		kvp.Int("content_len", len(content)),
	}...)
}

// recordAssistantChunk emits an assistant response as a chat.completion.chunk.
// single choice may contain with both content and tool_calls in the same delta when present (comparing with CCA)
// Format: {"object": "chat.completion.chunk", "choices": [{"finish_reason": "...", "delta": {"role": "assistant", "content": "...", "tool_calls": [...]}}]}
func (c *CAPIClient) recordAssistantChunk(ctx context.Context, content string, toolCalls []ToolCall, finishReason string, usage *models.TokenUsage) {
	recorder := c.getAvailableSessionRecorder(ctx)
	if recorder == nil {
		return
	}

	enhancedctx.Logger(ctx).Info("recording session chunk", []kvp.Field{
		kvp.String("finish_reason", finishReason),
		kvp.Int("tool_calls_count", len(toolCalls)),
		kvp.Int("content_len", len(content)),
	}...)

	delta := Delta{Role: "assistant"}
	if content != "" {
		delta.Content = content
	}
	if len(toolCalls) > 0 {
		delta.ToolCalls = toolCalls
	}

	recorder.Record(ctx, Chunk{
		ID:      fmt.Sprintf("cmpl-%d", time.Now().UnixNano()),
		Object:  "chat.completion.chunk",
		Created: time.Now().UnixMilli(),
		Model:   c.GetModelName(),
		Choices: []Choice{
			{
				Index:        0,
				FinishReason: finishReason,
				Delta:        delta,
			},
		},
		Usage: usage,
	})

	enhancedctx.Logger(ctx).Info("recorded assistant chunk", []kvp.Field{
		kvp.String("finish_reason", finishReason),
		kvp.Int("tool_calls_count", len(toolCalls)),
		kvp.Int("content_len", len(content)),
	}...)
}
