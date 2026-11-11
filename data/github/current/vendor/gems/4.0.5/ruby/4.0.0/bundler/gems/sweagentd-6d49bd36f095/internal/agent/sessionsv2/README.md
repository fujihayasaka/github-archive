# sessions-v2 payloads

This package translates progress payloads sent under the `sessions-v2` namespace.

A sessions-v2 progress item uses the standard progress envelope:

- `namespace`: `sessions-v2`
- `kind`: `log`
- `version`: `0`
- `content`: JSON object with one of the event payloads below

## Supported `content` payloads

### 1) Assistant message event

```json
{
  "kind": "message",
  "turn": 0,
  "callId": "call-1",
  "modelCall": { "model": "claude-sonnet-4.5" },
  "message": {
    "role": "assistant",
    "content": "I will inspect the code",
    "tool_calls": [
      {
        "id": "tc-1",
        "type": "function",
        "function": { "name": "read_file", "arguments": "{\"path\":\"main.go\"}" }
      }
    ]
  }
}
```

`message.content` is optional. When it is omitted, the translated session log item must also omit
`delta.content` so the UI can distinguish a pending setup row from a completed row with empty output.

### 2) Tool message event

```json
{
  "kind": "message",
  "turn": 0,
  "message": {
    "role": "tool",
    "tool_call_id": "tc-1",
    "content": "file contents..."
  }
}
```

### 3) Tool execution event

```json
{
  "kind": "tool_execution",
  "turn": 0,
  "callId": "call-1",
  "toolCallId": "tc-1",
  "toolName": "read_file",
  "toolResult": {
    "textResultForLlm": "tool result for the model",
    "sessionLog": "--- a/file.go\n+++ b/file.go\n@@ -1 +1 @@\n-old\n+new",
    "resultType": "success"
  },
  "originalCall": {
    "callId": "call-1",
    "model": "claude-sonnet-4.5",
    "toolCall": {
      "id": "tc-1",
      "type": "function",
      "function": { "name": "read_file", "arguments": "{\"path\":\"main.go\"}" }
    }
  }
}
```

`originalCall` is optional. When present, its `callId`, `model`, and `toolCall` fields are used to render the session log chunk. When it is missing, the translator can synthesize renderable tool-call context from the top-level `callId`, `toolCallId`, and `toolName` fields. If both `originalCall` and top-level `callId` are missing, the translator treats the event as telemetry/progress passthrough instead of a renderable session log item.

#### `toolResult` fields

| Field | Required | Description |
|---|---|---|
| `textResultForLlm` | yes | Model-facing result text. Always present, used as the content the LLM sees. |
| `sessionLog` | no | UI-facing detailed result (e.g. unified diff). When non-empty, the translator uses this instead of `textResultForLlm` for `delta.content` in the rendered session log so the UI can display rich output like edit diffs. |
| `detailedContent` | no | Alias for `sessionLog` used by some engines. Used when `sessionLog` is empty. |
| `resultType` | yes | `"success"` or `"failure"`. On failure the rendered text is wrapped in `<error>...</error>`. |

Precedence for rendered `delta.content`: `sessionLog` > `detailedContent` > `textResultForLlm`.

### 4) Response event

```json
{
  "kind": "response",
  "turn": 1,
  "callId": "call-2",
  "modelCall": { "model": "claude-sonnet-4.5" },
  "response": {
    "role": "assistant",
    "content": "Done. I fixed the issue."
  }
}
```

### 5) Telemetry passthrough event kinds

- `model_call_failure`
- `history_truncated`

### 6) Report progress event (side-effect)

Triggers a pull request title/description update. The event is stored as progress
and then the platform updates the associated PR. Both fields are optional; only
non-empty values are applied.

```json
{
  "kind": "report_progress",
  "pr_title": "Fix null pointer in UserService",
  "pr_description": "## Changes\n- [x] Added null check\n- [ ] Add tests"
}
```

The `kind` in the progress envelope must also be `report_progress`.

### 7) Comment reply event (side-effect)

Triggers a reply to a pull request comment. Used for `fix-pr-comment` actions.
The event is stored as progress and then the platform posts a reply to the
original comment and removes the 👀 reaction.

```json
{
  "kind": "comment_reply",
  "comment_id": 12345,
  "message": "I've addressed the feedback."
}
```

The `kind` in the progress envelope must also be `comment_reply`.
