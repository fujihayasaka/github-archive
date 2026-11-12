# Sessions Legacy Progress Schemas

**⚠️ DEPRECATED** - This namespace is deprecated and retained only for backward compatibility with existing sessions.

## Status

**Deprecated** - New progress schemas should use the `copilot` namespace instead.

## Contents

This directory contains legacy progress schemas that were used in the original sessions implementation:

| File | Kind | Description |
|------|------|-------------|
| `log.yaml` | `log` | Legacy session log format capturing OpenAI-style chat completions and messages (SSE-style) |
| `error.yaml` | `error` | Legacy error format with message and code properties |

## Available Kinds

### log

**Version:** 0
**Schema:** [log.yaml](./log.yaml)

Legacy session log format that captures OpenAI-style chat completion chunks and message parameters. This schema was designed for Server-Sent Events (SSE) style logging and represents either:

- **Chat completion chunks**: Streaming responses from the model during generation
- **Chat completion messages**: User messages, tool responses, or other message types

The log payload can be one of two main types:

1. **SessionsChatCompletionChunk**: Represents streaming model output with incremental deltas
2. **SessionsChatCompletionMessageParam**: Represents complete messages (user input, tool responses)

**Example Usage - Chat Completion Chunk:**

```json
{
  "namespace": "sessions-legacy",
  "kind": "log",
  "version": 0,
  "content": "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1701453600,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello! How can I help you today?\"},\"finish_reason\":null}]}"
}
```

**Example Usage - User Message:**

```json
{
  "namespace": "sessions-legacy",
  "kind": "log",
  "version": 0,
  "content": "{\"role\":\"user\",\"content\":\"Fix the bug in the authentication module\",\"source\":\"jit-instruction\"}"
}
```

**Example Usage - Tool Message:**

```json
{
  "namespace": "sessions-legacy",
  "kind": "log",
  "version": 0,
  "content": "{\"role\":\"tool\",\"content\":\"File contents: ...\",\"tool_call_id\":\"call_abc123\"}"
}
```

**Payload Schema:**

The payload is a `SessionLogsContent` object which can be either:

- **SessionsChatCompletionChunk**: OpenAI chat completion chunk with:
  - `id` (required): Unique identifier for the chat completion
  - `object` (required): Always `"chat.completion.chunk"`
  - `created` (required): Unix timestamp
  - `model` (required): Model identifier
  - `choices` (required): Array of chunk choices with delta content
  - `agentId` (optional): Agent invocation identifier

- **SessionsChatCompletionMessageParam**: Message parameter with:
  - `role` (required): Message role (`"user"`, `"tool"`, etc.)
  - `content` (required): Message content (string or structured)
  - `tool_call_id` (required for tool messages): Tool call identifier
  - `source` (optional for user messages): Source component identifier
  - `agentId` (optional): Agent invocation identifier

### error

**Version:** 0
**Schema:** [error.yaml](./error.yaml)

Simple error messages for backward compatibility. Each error includes a human-readable message and an optional machine-readable code.

**Example Usage:**

Minimal example:

```json
{
  "namespace": "sessions-legacy",
  "kind": "error",
  "version": 0,
  "content": "{\"message\":\"Failed to execute command\"}"
}
```

Example with optional code:

```json
{
  "namespace": "sessions-legacy",
  "kind": "error",
  "version": 0,
  "content": "{\"message\":\"Failed to execute command\",\"code\":\"command_failed\"}"
}
```

**Payload Schema:**

- `message` (required): Human-readable error message
- `code` (optional): Machine-readable error code

## Usage Examples

### Creating Log Entries

#### Example 1: Logging a streaming model response chunk

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "sessions-legacy",
    "kind": "log",
    "version": 0,
    "content": "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1701453600,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello! \"},\"finish_reason\":null}]}"
  }'
```

#### Example 2: Logging a user message

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "sessions-legacy",
    "kind": "log",
    "version": 0,
    "content": "{\"role\":\"user\",\"content\":\"Fix the bug in the authentication module\"}"
  }'
```

#### Example 3: Logging a tool response

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "sessions-legacy",
    "kind": "log",
    "version": 0,
    "content": "{\"role\":\"tool\",\"content\":\"File read successfully. Contents: function authenticate() { ... }\",\"tool_call_id\":\"call_abc123\"}"
  }'
```

#### Example 4: Batch logging multiple entries

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "namespace": "sessions-legacy",
      "kind": "log",
      "version": 0,
      "content": "{\"role\":\"user\",\"content\":\"Analyze the codebase\"}"
    },
    {
      "namespace": "sessions-legacy",
      "kind": "log",
      "version": 0,
      "content": "{\"id\":\"chatcmpl-456\",\"object\":\"chat.completion.chunk\",\"created\":1701453601,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"I will analyze\"},\"finish_reason\":null}]}"
    }
  ]'
```

## Migration

**Do not use these schemas for new integrations.** Instead:

1. Use the `copilot` namespace for well-known progress types
2. Define custom namespaces for integrator-specific needs

See the main [Progress documentation](../README.md) for details on current progress schemas.

## Why Deprecated?

The `sessions-legacy` namespace was designed for an older iteration of the progress system. It has several limitations:

- SSE-style formatting that doesn't align with the current REST API design
- Limited extensibility for new use cases
- Tight coupling to the original sessions implementation and CAPI completions response format

The new `copilot` namespace provides:

- Better alignment with modern REST API patterns
- Improved schema extensibility
- Cleaner separation of concerns between well-known and custom schemas

## Removal Timeline

The `sessions-legacy` namespace will be supported for existing sessions but should not be used for new development. A future API version may remove support entirely. Please plan to migrate to the `copilot` namespace when available.
