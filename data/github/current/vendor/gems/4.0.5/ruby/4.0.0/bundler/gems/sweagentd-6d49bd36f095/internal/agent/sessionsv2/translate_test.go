package sessionsv2

import (
	"encoding/json"
	"testing"
)

func decodeChunk(t *testing.T, raw json.RawMessage) sessionLogChunk {
	t.Helper()

	var chunk sessionLogChunk
	err := json.Unmarshal(raw, &chunk)
	if err != nil {
		t.Fatalf("failed to parse session log chunk: %v", err)
	}

	return chunk
}

func decodeToolMessage(t *testing.T, raw json.RawMessage) sessionLogToolMessage {
	t.Helper()

	var msg sessionLogToolMessage
	err := json.Unmarshal(raw, &msg)
	if err != nil {
		t.Fatalf("failed to parse session log tool message: %v", err)
	}

	return msg
}

func TestTranslateAssistantMessage(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"callId": "call-1",
		"modelCall": { "model": "claude-sonnet-4.5" },
		"message": {
			"role": "assistant",
			"content": "I will fix the bug.",
			"tool_calls": [
				{
					"id": "tc-1",
					"type": "function",
					"function": { "name": "read_file", "arguments": "{\"path\":\"main.go\"}" }
				}
			]
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Object != "chat.completion.chunk" {
		t.Fatalf("expected object 'chat.completion.chunk', got %q", chunk.Object)
	}
	if chunk.ID != "call-1" {
		t.Fatalf("expected id 'call-1', got %q", chunk.ID)
	}
	if chunk.Model != "claude-sonnet-4.5" {
		t.Fatalf("expected model 'claude-sonnet-4.5', got %q", chunk.Model)
	}
	if len(chunk.Choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(chunk.Choices))
	}
	if chunk.Choices[0].FinishReason == nil || *chunk.Choices[0].FinishReason != "tool_calls" {
		t.Fatal("expected finish_reason 'tool_calls'")
	}
	if len(chunk.Choices[0].Delta.ToolCalls) != 1 {
		t.Fatalf("expected 1 tool call, got %d", len(chunk.Choices[0].Delta.ToolCalls))
	}
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "I will fix the bug." {
		t.Fatalf("expected content 'I will fix the bug.', got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateAssistantMessageWithoutContentOmitsContentField(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"callId": "call-setup-1",
		"message": {
			"role": "assistant",
			"tool_calls": [
				{
					"id": "tc-setup-1",
					"type": "function",
					"function": { "name": "run_setup", "arguments": "{\"name\":\"Clone repository github/example\"}" }
				}
			]
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content != nil {
		t.Fatalf("expected nil content, got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolMessage(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"message": {
			"role": "tool",
			"tool_call_id": "tc-1",
			"content": "file contents here"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	msg := decodeToolMessage(t, result.SessionLog)
	if msg.Role != "tool" {
		t.Fatalf("expected role 'tool', got %q", msg.Role)
	}
	if msg.ToolCallID != "tc-1" {
		t.Fatalf("expected tool_call_id 'tc-1', got %q", msg.ToolCallID)
	}
}

func TestTranslateToolExecutionWithOriginalCall(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "package main",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "read_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.ID != "call-1" {
		t.Fatalf("expected id 'call-1', got %q", chunk.ID)
	}
	if chunk.Model != "claude-sonnet-4.5" {
		t.Fatalf("expected model 'claude-sonnet-4.5', got %q", chunk.Model)
	}
	if len(chunk.Choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(chunk.Choices))
	}
	if chunk.Choices[0].FinishReason == nil || *chunk.Choices[0].FinishReason != "tool_calls" {
		t.Fatal("expected finish_reason 'tool_calls'")
	}
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "package main" {
		t.Fatalf("expected content 'package main', got %#v", chunk.Choices[0].Delta.Content)
	}
	if len(chunk.Choices[0].Delta.ToolCalls) != 1 {
		t.Fatalf("expected 1 tool call, got %d", len(chunk.Choices[0].Delta.ToolCalls))
	}
	if chunk.Choices[0].Delta.ToolCalls[0].ID != "tc-1" {
		t.Fatalf("expected tool call id 'tc-1', got %q", chunk.Choices[0].Delta.ToolCalls[0].ID)
	}
}

func TestTranslateToolExecutionFailureWrapsError(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-2",
		"toolResult": {
			"textResultForLlm": "permission denied",
			"resultType": "failure"
		},
		"originalCall": {
			"callId": "call-2",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-2",
				"type": "function",
				"function": { "name": "write_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if len(chunk.Choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(chunk.Choices))
	}

	expected := "<error>permission denied</error>"
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != expected {
		t.Fatalf("expected content %q, got %#v", expected, chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionWithoutOriginalCallIsProgress(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-3",
		"toolResult": {
			"textResultForLlm": "some result",
			"resultType": "success"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "progress" {
		t.Fatalf("expected kind 'progress', got %q", result.Kind)
	}
}

func TestTranslateResponse(t *testing.T) {
	event := `{
		"kind": "response",
		"turn": 1,
		"callId": "call-4",
		"response": {
			"role": "assistant",
			"content": "I have fixed the bug."
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if len(chunk.Choices) != 1 {
		t.Fatalf("expected 1 choice, got %d", len(chunk.Choices))
	}
	if chunk.Choices[0].FinishReason == nil || *chunk.Choices[0].FinishReason != "stop" {
		t.Fatal("expected finish_reason 'stop'")
	}
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "I have fixed the bug." {
		t.Fatalf("expected content 'I have fixed the bug.', got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateModelCallFailurePassthrough(t *testing.T) {
	event := `{
		"kind": "model_call_failure",
		"turn": 0,
		"callId": "call-5",
		"modelCall": { "error": "rate limited" }
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "progress" {
		t.Fatalf("expected kind 'progress', got %q", result.Kind)
	}
}

func TestTranslateWithKindTelemetryPassthroughFallback(t *testing.T) {
	event := `{"turn":0,"callId":"call-5","modelCall":{"error":"rate limited"}}`

	result, err := TranslateWithKind(KindModelCallFailure, json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "progress" {
		t.Fatalf("expected kind 'progress', got %q", result.Kind)
	}
	if string(result.SessionLog) != event {
		t.Fatalf("expected passthrough content %s, got %s", event, result.SessionLog)
	}
}

func TestTranslateWithKindDoesNotFallbackForSideEffectKind(t *testing.T) {
	event := `{"pr_title":"New title","pr_description":"New description"}`

	_, err := TranslateWithKind(KindReportProgress, json.RawMessage(event))
	if err == nil {
		t.Fatal("expected error for missing content kind, got nil")
	}
}

func TestTranslateWithKindDoesNotFallbackForRenderableKind(t *testing.T) {
	event := `{"message":{"role":"assistant","content":"missing event kind"}}`

	_, err := TranslateWithKind(KindMessage, json.RawMessage(event))
	if err == nil {
		t.Fatal("expected error for missing content kind, got nil")
	}
}

func TestTranslateUnknownKind(t *testing.T) {
	event := `{"kind": "unknown_thing"}`
	_, err := TranslateWithKind("", json.RawMessage(event))
	if err == nil {
		t.Fatal("expected error for unknown kind, got nil")
	}
}

func TestTranslateUserMessage(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 3,
		"source": "command-123",
		"message": {
			"role": "user",
			"content": "please also fix the typo on line 42"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	var msg sessionLogUserMessage
	unmarshalErr := json.Unmarshal(result.SessionLog, &msg)
	if unmarshalErr != nil {
		t.Fatalf("failed to parse session log user message: %v", unmarshalErr)
	}
	if msg.Role != "user" {
		t.Fatalf("expected role 'user', got %q", msg.Role)
	}
	if msg.Content != "please also fix the typo on line 42" {
		t.Fatalf("expected content 'please also fix the typo on line 42', got %q", msg.Content)
	}
	if msg.Source != "command-123" {
		t.Fatalf("expected source 'command-123', got %q", msg.Source)
	}
}

func TestTranslateUserMessageWithoutSource(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"message": {
			"role": "user",
			"content": "hello world"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	var msg sessionLogUserMessage
	unmarshalErr := json.Unmarshal(result.SessionLog, &msg)
	if unmarshalErr != nil {
		t.Fatalf("failed to parse session log user message: %v", unmarshalErr)
	}
	if msg.Role != "user" {
		t.Fatalf("expected role 'user', got %q", msg.Role)
	}
	if msg.Content != "hello world" {
		t.Fatalf("expected content 'hello world', got %q", msg.Content)
	}
	if msg.Source != "" {
		t.Fatalf("expected empty source, got %q", msg.Source)
	}
}

func TestTranslateAssistantMessageWithAgentID(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"callId": "call-1",
		"agentId": "sub-agent-1",
		"modelCall": { "model": "claude-sonnet-4.5" },
		"message": {
			"role": "assistant",
			"content": "I will fix the bug."
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.AgentID != "sub-agent-1" {
		t.Fatalf("expected agentId 'sub-agent-1', got %q", chunk.AgentID)
	}
}

func TestTranslateToolMessageWithAgentID(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"agentId": "sub-agent-2",
		"message": {
			"role": "tool",
			"tool_call_id": "tc-1",
			"content": "file contents here"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	msg := decodeToolMessage(t, result.SessionLog)
	if msg.AgentID != "sub-agent-2" {
		t.Fatalf("expected agentId 'sub-agent-2', got %q", msg.AgentID)
	}
}

func TestTranslateUserMessageWithAgentID(t *testing.T) {
	event := `{
		"kind": "message",
		"turn": 0,
		"agentId": "sub-agent-3",
		"message": {
			"role": "user",
			"content": "hello from subagent"
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	var msg sessionLogUserMessage
	unmarshalErr := json.Unmarshal(result.SessionLog, &msg)
	if unmarshalErr != nil {
		t.Fatalf("failed to parse session log user message: %v", unmarshalErr)
	}
	if msg.AgentID != "sub-agent-3" {
		t.Fatalf("expected agentId 'sub-agent-3', got %q", msg.AgentID)
	}
}

func TestTranslateToolExecutionWithAgentID(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"agentId": "sub-agent-4",
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "package main",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "read_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.AgentID != "sub-agent-4" {
		t.Fatalf("expected agentId 'sub-agent-4', got %q", chunk.AgentID)
	}
}

func TestTranslateToolExecutionPrefersSessionLog(t *testing.T) {
	diff := "--- a/file.go\n+++ b/file.go\n@@ -1 +1 @@\n-old\n+new"
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "concise model text",
			"sessionLog": "--- a/file.go\n+++ b/file.go\n@@ -1 +1 @@\n-old\n+new",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "edit_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != diff {
		t.Fatalf("expected sessionLog diff in content, got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionPrefersDetailedContent(t *testing.T) {
	detailed := "detailed content for UI"
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "concise model text",
			"detailedContent": "` + detailed + `",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "edit_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != detailed {
		t.Fatalf("expected detailedContent in content, got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionSessionLogBeatsDetailedContent(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "model text",
			"sessionLog": "session log wins",
			"detailedContent": "detailed content loses",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "edit_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "session log wins" {
		t.Fatalf("expected sessionLog to take precedence, got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionSessionLogFailureWrapsError(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "model error",
			"sessionLog": "detailed error output",
			"resultType": "failure"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "edit_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	expected := "<error>detailed error output</error>"
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != expected {
		t.Fatalf("expected %q, got %#v", expected, chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionFallsBackToTextResultForLlm(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-1",
		"toolResult": {
			"textResultForLlm": "fallback text",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "tc-1",
				"type": "function",
				"function": { "name": "read_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "fallback text" {
		t.Fatalf("expected textResultForLlm fallback, got %#v", chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionUsesTopLevelCallContext(t *testing.T) {
	diff := "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-Test\n+josebalius"
	event := `{
		"kind": "tool_execution",
		"turn": 2,
		"callId": "call-edit-1",
		"toolCallId": "tc-edit-1",
		"toolName": "edit",
		"toolResult": {
			"textResultForLlm": "File /tmp/workspace/josebalius/dotfiles/README.md updated with changes.",
			"sessionLog": "--- a/README.md\n+++ b/README.md\n@@ -1 +1 @@\n-Test\n+josebalius",
			"resultType": "success",
			"toolTelemetry": {}
		},
		"durationMs": 42
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.ID != "call-edit-1" {
		t.Fatalf("expected chunk id 'call-edit-1', got %q", chunk.ID)
	}
	if chunk.Model != "unknown" {
		t.Fatalf("expected fallback model 'unknown', got %q", chunk.Model)
	}
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != diff {
		t.Fatalf("expected sessionLog diff in content, got %#v", chunk.Choices[0].Delta.Content)
	}
	if len(chunk.Choices[0].Delta.ToolCalls) != 1 {
		t.Fatalf("expected 1 tool call, got %d", len(chunk.Choices[0].Delta.ToolCalls))
	}
	tc := chunk.Choices[0].Delta.ToolCalls[0]
	if tc.ID != "tc-edit-1" {
		t.Fatalf("expected tool call id 'tc-edit-1', got %q", tc.ID)
	}
	if tc.Type != "function" {
		t.Fatalf("expected tool call type 'function', got %q", tc.Type)
	}
	if tc.Function.Name != "edit" {
		t.Fatalf("expected function name 'edit', got %q", tc.Function.Name)
	}
	if tc.Function.Arguments != "" {
		t.Fatalf("expected empty synthesized arguments, got %q", tc.Function.Arguments)
	}
}

func TestTranslateToolExecutionTopLevelCallContextFallsBackToTextResultForLlm(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 1,
		"callId": "call-view-1",
		"toolCallId": "tc-view-1",
		"toolName": "view",
		"toolResult": {
			"textResultForLlm": "file contents here",
			"resultType": "success",
			"toolTelemetry": {}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != "file contents here" {
		t.Fatalf("expected textResultForLlm fallback, got %#v", chunk.Choices[0].Delta.Content)
	}
	if chunk.Choices[0].Delta.ToolCalls[0].Function.Name != "view" {
		t.Fatalf("expected function name 'view', got %q", chunk.Choices[0].Delta.ToolCalls[0].Function.Name)
	}
}

func TestTranslateToolExecutionTopLevelCallContextFailureWrapsSessionLog(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 2,
		"callId": "call-edit-failure",
		"toolCallId": "tc-edit-failure",
		"toolName": "edit",
		"toolResult": {
			"textResultForLlm": "permission denied",
			"sessionLog": "detailed error with context",
			"resultType": "failure",
			"toolTelemetry": {}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	expected := "<error>detailed error with context</error>"
	if chunk.Choices[0].Delta.Content == nil || *chunk.Choices[0].Delta.Content != expected {
		t.Fatalf("expected %q, got %#v", expected, chunk.Choices[0].Delta.Content)
	}
}

func TestTranslateToolExecutionFallsBackToTopLevelToolCallID(t *testing.T) {
	event := `{
		"kind": "tool_execution",
		"turn": 0,
		"toolCallId": "tc-fallback",
		"toolResult": {
			"textResultForLlm": "result",
			"resultType": "success"
		},
		"originalCall": {
			"callId": "call-1",
			"model": "claude-sonnet-4.5",
			"toolCall": {
				"id": "",
				"type": "function",
				"function": { "name": "read_file", "arguments": "{}" }
			}
		}
	}`

	result, err := TranslateWithKind("", json.RawMessage(event))
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if result.Kind != "log" {
		t.Fatalf("expected kind 'log', got %q", result.Kind)
	}

	chunk := decodeChunk(t, result.SessionLog)
	if chunk.Choices[0].Delta.ToolCalls[0].ID != "tc-fallback" {
		t.Fatalf("expected tool call id 'tc-fallback', got %q", chunk.Choices[0].Delta.ToolCalls[0].ID)
	}
}
