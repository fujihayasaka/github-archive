package provider

import (
	"context"
	"time"

	"github.com/github/code-scanning-ai-libraries/v3/llm/models"
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
	Role             string     `json:"role,omitempty"`
	Content          string     `json:"content,omitempty"`
	ToolCalls        []ToolCall `json:"tool_calls,omitempty"`
	ReasoningOpaque  string     `json:"reasoning_opaque,omitempty"`
	ReasoningText    string     `json:"reasoning_text,omitempty"`
	EncryptedContent string     `json:"encrypted_content,omitempty"`
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

// BuildAssistantContentChunk is a helper which creates a simple assistant content chunk.
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

// storedReasoningKeyType is used to store reasoning messages in context for later merging with tool calls.
type storedReasoningKeyType struct{}

var contextKeyStoredReasoning = storedReasoningKeyType{}

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

// withStoredReasoning stores a reasoning message in the context for later merging with tool calls
func withStoredReasoning(ctx context.Context, reasoning *models.ChatMessage) context.Context {
	return context.WithValue(ctx, contextKeyStoredReasoning, reasoning)
}

// getStoredReasoning retrieves the stored reasoning message from context, if any
func getStoredReasoning(ctx context.Context) *models.ChatMessage {
	if reasoning, ok := ctx.Value(contextKeyStoredReasoning).(*models.ChatMessage); ok {
		return reasoning
	}
	return nil
}

func clearStoredReasoning(ctx context.Context) context.Context {
	if getStoredReasoning(ctx) == nil {
		return ctx
	}
	return context.WithValue(ctx, contextKeyStoredReasoning, (*models.ChatMessage)(nil))
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
