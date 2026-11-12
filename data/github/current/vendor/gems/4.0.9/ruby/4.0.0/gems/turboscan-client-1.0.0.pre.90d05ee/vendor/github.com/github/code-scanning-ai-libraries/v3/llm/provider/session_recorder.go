package provider

import (
	"context"
	"fmt"
	"time"

	"github.com/github/code-scanning-ai-libraries/v3/enhancedctx"
	"github.com/github/code-scanning-ai-libraries/v3/llm/models"
	"github.com/github/github-telemetry-go/kvp"
)

// SessionRecorderManager provides unified session recording functionality for both chat and responses model calls.
// Session recorders are retrieved from context using WithSessionRecorder().
type SessionRecorderManager struct {
	modelName string
}

// NewSessionRecorderManager creates a new session recording manager
func NewSessionRecorderManager(modelName string) *SessionRecorderManager {
	return &SessionRecorderManager{
		modelName: modelName,
	}
}

// HasRecorder checks if session recording is enabled
func (s *SessionRecorderManager) HasRecorder(ctx context.Context) bool {
	return getSessionRecorder(ctx) != nil
}

// GetRecorder retrieves the session recorder from context
func (s *SessionRecorderManager) GetRecorder(ctx context.Context) SessionRecorder {
	return getSessionRecorder(ctx)
}

// RecordUserMessages records user messages with deduplication
func (s *SessionRecorderManager) RecordUserMessages(ctx context.Context, messages []models.ChatMessage) context.Context {
	if s == nil || wereUserMessagesRecorded(ctx) {
		return ctx
	}

	recorder := s.GetRecorder(ctx)
	if recorder == nil {
		return ctx
	}

	recordedCount := 0
	for _, msg := range messages {
		if msg.Role == "user" {
			recorder.Record(ctx, map[string]any{"role": string(msg.Role), "content": msg.Content})
			recordedCount++
		}
	}
	enhancedctx.Logger(ctx).Info("recorded user messages", kvp.Int("count", recordedCount))

	return markUserMessagesRecorded(ctx)
}

// RecordAssistantChunk records assistant response in standard chat.completion.chunk format
func (s *SessionRecorderManager) RecordAssistantChunk(ctx context.Context, content string, toolCalls []ToolCall, finishReason string, usage *models.TokenUsage) {
	delta := Delta{Role: "assistant"}
	if content != "" {
		delta.Content = content
	}
	if len(toolCalls) > 0 {
		delta.ToolCalls = toolCalls
	}

	s.recordIfSessionPresentWithID(ctx, fmt.Sprintf("cmpl-%d", time.Now().UnixNano()), delta, finishReason, usage, []kvp.Field{
		kvp.String("finish_reason", finishReason),
		kvp.Int("tool_calls_count", len(toolCalls)),
		kvp.Int("content_len", len(content)),
	}, "recorded assistant chunk")
}

// RecordToolCallWithResult records a tool call with its result in a single chunk.
// For Responses API, pass originalMsg to preserve reasoning fields. For Chat Completions API, pass empty ChatMessage.
func (s *SessionRecorderManager) RecordToolCallWithResult(ctx context.Context, toolCall models.ToolCall, content string, originalMsg models.ChatMessage) context.Context {
	delta := Delta{
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
	}

	// Preserve reasoning fields if present
	s.addReasoningFieldsToDelta(&delta, originalMsg)

	// Merge stored reasoning if available (provides Summary/reasoning_text). This is a fallback
	// for tool-call messages that don't carry reasoning fields; it must be consumed (`clearStoredReasoning`)
	// to avoid duplicating the same summary across multiple tool calls in the same response.
	if storedReasoning := getStoredReasoning(ctx); storedReasoning != nil {
		s.addReasoningFieldsToDelta(&delta, *storedReasoning)
		ctx = clearStoredReasoning(ctx)
	}

	logMessage := "recorded tool call with result"
	if delta.ReasoningText != "" {
		logMessage = "recorded tool call with reasoning"
	}

	s.recordIfSessionPresentWithID(ctx, fmt.Sprintf("cmpl-%d", time.Now().UnixNano()), delta, FinishReasonToolCalls, nil, []kvp.Field{
		kvp.String("tool_call_id", toolCall.ID),
		kvp.String("tool_name", toolCall.Function.Name),
		kvp.String("arguments", toolCall.Function.Arguments),
		kvp.Int("output_len", len(content)),
		kvp.Bool("has_reasoning", delta.ReasoningText != ""),
		kvp.Int("reasoning_text_len", len(delta.ReasoningText)),
	}, logMessage)

	return ctx
}

// RecordError records API errors in structured format
func (s *SessionRecorderManager) RecordError(ctx context.Context, err error, usage *models.TokenUsage) {
	if s == nil || !s.HasRecorder(ctx) {
		return
	}
	s.RecordAssistantChunk(ctx, formatError(err), nil, FinishReasonStop, usage)
}

// RecordResponsesOutput logs reasoning sections and assistant messages from Responses API.
// Stores reasoning in context to merge with tool calls later.
//
//nolint:fatcontext // We intentionally store only the last reasoning message.
func (s *SessionRecorderManager) RecordResponsesOutput(ctx context.Context, responseID string, messages []models.ChatMessage, usage *models.TokenUsage) context.Context {
	if s == nil || !s.HasRecorder(ctx) {
		return ctx
	}

	for _, msg := range messages {
		switch msg.Type {
		case "reasoning":
			// Store reasoning in context to merge with next tool call
			// Sessions UI only checks reasoning_text when tool_calls exist, so we don't record standalone.
			// See https://github.com/github/agent-session-experience/issues/615
			if existingReasoning := getStoredReasoning(ctx); existingReasoning != nil {
				enhancedctx.Logger(ctx).Warn("overwriting unused reasoning", []kvp.Field{
					kvp.String("old_reasoning_id", existingReasoning.ID),
					kvp.String("new_reasoning_id", msg.ID),
				}...)
			}
			reasoningCopy := msg
			ctx = withStoredReasoning(ctx, &reasoningCopy)
			enhancedctx.Logger(ctx).Info("stored reasoning for next tool call", []kvp.Field{
				kvp.String("reasoning_id", msg.ID),
				kvp.Bool("has_summary", msg.Summary != nil),
			}...)

		case "function_call", "custom_tool_call":
			// Skipped - logged separately with results via RecordToolCallWithResult
			continue

		case "message":
			// Record assistant message
			if msg.Role == "assistant" {
				s.RecordAssistantChunk(ctx, msg.Content, nil, FinishReasonStop, usage)
			}
		}
	}

	return ctx
}

// addReasoningFieldsToDelta extracts reasoning fields from a message and adds them to the delta
func (s *SessionRecorderManager) addReasoningFieldsToDelta(delta *Delta, msg models.ChatMessage) {
	if msg.ID != "" {
		delta.ReasoningOpaque = msg.ID
	}
	if msg.EncryptedContent != "" {
		delta.EncryptedContent = msg.EncryptedContent
	}
	if msg.Summary != nil && len(*msg.Summary) > 0 {
		reasoningText := ""
		for i, summary := range *msg.Summary {
			if i > 0 {
				reasoningText += " "
			}
			reasoningText += summary.Text
		}
		delta.ReasoningText += reasoningText
	}
}

// recordIfSessionPresentWithID records a delta with a specific chunk ID if a session recorder is present
func (s *SessionRecorderManager) recordIfSessionPresentWithID(ctx context.Context, chunkID string, delta Delta, finishReason string, usage *models.TokenUsage, logFields []kvp.Field, logMessage string) {
	if s == nil {
		return
	}
	recorder := s.GetRecorder(ctx)
	if recorder == nil {
		return
	}

	recorder.Record(ctx, Chunk{
		ID:      chunkID,
		Object:  "chat.completion.chunk",
		Created: time.Now().UnixMilli(),
		Model:   s.modelName,
		Choices: []Choice{
			{
				Index:        0,
				FinishReason: finishReason,
				Delta:        delta,
			},
		},
		Usage: usage,
	})

	enhancedctx.Logger(ctx).Info(logMessage, logFields...)
}

// ConvertResponsesToolCall converts Responses API tool call format to Chat Completions format
func ConvertResponsesToolCall(msg models.ChatMessage) models.ToolCall {
	return models.ToolCall{
		ID: msg.CallID,
		Function: struct {
			Name      string `json:"name,omitempty"`
			Arguments string `json:"arguments,omitempty"`
		}{
			Name:      msg.Name,
			Arguments: msg.Arguments,
		},
	}
}
