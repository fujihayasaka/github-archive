# Agent Progress

`Progress` represents an incremental progress update for an agent job/session. This can be a log, status update, error, native SDK output, or any other information about the job's progress.

## Overview

Progress has three properties that enable the type to support polymorphic update types: `namespace`, `version`, and `kind`. Together these three properties define the schema of the progress update payload. This allows the service to define first-party progress update types, while also allowing third-party integrators to define their own custom progress update types.

First-party progress update types are defined by the service and will have well-known `namespace`, `version`, and `kind` values that map to published payload schemas. For example, a first-party error update that should be displayed to the user might have the following properties:

- **Namespace**: `copilot`
- **Version**: `1`
- **Kind**: `error`

Third-party integrators can define their own progress update types by choosing unique `namespace`, `version`, and `kind` values that do not conflict with first-party types. This allows integrators to send custom progress updates that can be interpreted by their own systems or tools.

## Object

A progress object represents a single progress update for a job. The complete structure is:

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier of the progress entry (assigned by the server) |
| `namespace` | string | Yes | Namespace of the progress update (e.g., "copilot", "claude.code") |
| `kind` | string | Yes | The kind of progress update within the namespace (e.g., "error", "log") |
| `version` | integer | Yes | Version of the progress update payload schema |
| `content` | string | Yes | JSON-encoded payload as a UTF-8 string |
| `created_at` | integer | Yes | Unix timestamp (seconds since epoch) when the entry was created |

### Example Progress Object

```json
{
  "id": "01234567-89ab-cdef-0123-456789abcdef",
  "namespace": "copilot",
  "kind": "error",
  "version": 0,
  "content": "{\"message\":\"Failed to parse configuration file\",\"code\":\"parse_error\",\"severity\":\"error\"}",
  "created_at": 1701453600
}
```

### Content Payload

The `content` field is a JSON string that must be parsed to access the actual payload. The structure of the parsed JSON depends on the `namespace`, `kind`, and `version` of the progress update.

For well-known progress types, the payload structure is defined in OpenAPI specifications (see the [Schemas](#schemas) section below). For custom progress types, integrators define their own payload structures.

## Schemas

Progress schemas are organized into namespaces, with each namespace containing one or more kinds of progress updates. Schema definitions are provided as OpenAPI YAML files under subdirectories of this folder.

### Well-Known Schemas

The child folders under `progress/` represent different progress schema **namespaces**. The YAML files within these folders define different **kinds** in the form of OpenAPI specifications.

These well-known namespaces and kinds represent **first-party progress schemas** that integrate with system functionality:

- **github.com mission control UI**: Displays errors, logs, and other progress updates
- **VS Code**: Shows progress in the Copilot panel
- **Other GitHub UIs**: Future integration points for progress visualization

Using well-known schemas ensures that your progress updates are properly rendered and surfaced in these system interfaces.

### Custom Schemas

Custom progress schemas can be defined by agents and **do not need to be in these well-known namespaces to be valid**. Any agent can create progress updates with custom namespace/kind/version combinations to store integrator-specific data.

Custom schemas are useful for:

- Storing native SDK output that needs to be preserved across sessions
- Tracking agent-specific metrics or state
- Integrating with third-party tools that understand your custom schema
- Recording debug information that doesn't fit well-known schemas

### Schema Summary

The following table lists the currently available well-known progress schemas:

| Namespace | Kind | Version | Description | Status |
|-----------|------|---------|-------------|--------|
| `sessions-legacy` | `log` | 0 | Legacy session log format (SSE-style) | **Deprecated** |
| `sessions-legacy` | `error` | 0 | Legacy error format | **Deprecated** |
| `copilot` | `error` | 0 | Error messages with severity levels | **Available** |
| `code-review` | *(integrator-defined)* | *(integrator-defined)* | Code review findings (CCR, 3P engines). See [ADR-0012](../../../docs/adr/0012-progress-api-code-review-namespaces.md) | **Available** |
| `code-scanning-security` | *(integrator-defined)* | *(integrator-defined)* | Code Scanning review findings. See [ADR-0012](../../../docs/adr/0012-progress-api-code-review-namespaces.md) | **Available** |
| `sessions-v2` | `message` | 0 | Assistant/tool message events | **Available** |
| `sessions-v2` | `tool_execution` | 0 | Tool execution results and telemetry | **Available** |
| `sessions-v2` | `response` | 0 | Final agent response for a turn | **Available** |
| `sessions-v2` | `model_call_failure` | 0 | LLM API call failure telemetry | **Available** |
| `sessions-v2` | `history_truncated` | 0 | Context window truncation telemetry | **Available** |
| `sessions-v2` | `report_progress` | 0 | PR title/description update (side-effect) | **Available** |
| `sessions-v2` | `comment_reply` | 0 | Reply to a PR comment (side-effect) | **Available** |

> **Note**: The `sessions-legacy` namespace is **deprecated** and retained only for backward compatibility with existing sessions. New integrations should use `sessions-v2`. See the [sessions-v2 documentation](../../../internal/agent/sessionsv2/README.md) for payload schemas and side-effect behavior.
>
> **First-party integrators**: See the [Integrating Guide](./INTEGRATING.md) for how to add a new namespace to the emit list.

### Schema Files

Schema files are organized as follows:

```plaintext
progress/
├── README.md                    # This file
├── INTEGRATING.md               # Guide for first-party integrators
├── copilot/                     # Well-known copilot namespace
│   ├── README.md                # Copilot namespace documentation
│   └── error.yaml               # Error schema (v0)
└── sessions-legacy/             # Deprecated legacy namespace
    ├── error.yaml               # Legacy error schema
    └── log.yaml                 # Legacy log schema
```

The `sessions-v2` namespace payloads are documented in the [sessions-v2 package README](../../../internal/agent/sessionsv2/README.md) alongside the server-side translation logic.

Each YAML file contains an OpenAPI specification describing the payload structure for that particular kind of progress update.

## Usage Examples

### Creating a Well-Known Progress Update

When using a well-known schema like `copilot/error`, the content payload should conform to the published schema:

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "copilot",
    "kind": "error",
    "version": 0,
    "content": "{\"message\":\"Failed to parse configuration file\",\"code\":\"parse_error\",\"severity\":\"error\"}"
  }'
```

**Response:**

```json
{
  "id": "01234567-89ab-cdef-0123-456789abcdef",
  "namespace": "copilot",
  "kind": "error",
  "version": 0,
  "content": "{\"message\":\"Failed to parse configuration file\",\"code\":\"parse_error\",\"severity\":\"error\"}",
  "created_at": 1701453600
}
```

### Creating a Custom Progress Update

Custom progress updates can use any namespace/kind combination that doesn't conflict with well-known schemas:

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "my-company.agent",
    "kind": "metric",
    "version": 0,
    "content": "{\"cpu_usage\":45.2,\"memory_mb\":1024,\"timestamp\":1701453600}"
  }'
```

**Response:**

```json
{
  "id": "98765432-10fe-dcba-9876-543210fedcba",
  "namespace": "my-company.agent",
  "kind": "metric",
  "version": 0,
  "content": "{\"cpu_usage\":45.2,\"memory_mb\":1024,\"timestamp\":1701453600}",
  "created_at": 1701453600
}
```

### Batch Creating Progress Updates

Create multiple progress updates in a single request with all-or-nothing semantics:

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
      "content": "{\"role\":\"user\",\"content\":\"Starting task execution\"}"
    },
    {
      "namespace": "sessions-legacy",
      "kind": "log",
      "version": 0,
      "content": "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1701453600,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Task completed successfully\"},\"finish_reason\":\"stop\"}]}"
    }
  ]'
```

**Response:**

```json
[
  {
    "id": "11111111-1111-1111-1111-111111111111",
    "namespace": "sessions-legacy",
    "kind": "log",
    "version": 0,
    "content": "{\"role\":\"user\",\"content\":\"Starting task execution\"}",
    "created_at": 1701453600
  },
  {
    "id": "22222222-2222-2222-2222-222222222222",
    "namespace": "sessions-legacy",
    "kind": "log",
    "version": 0,
    "content": "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion.chunk\",\"created\":1701453600,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Task completed successfully\"},\"finish_reason\":\"stop\"}]}",
    "created_at": 1701453601
  }
]
```

### Retrieving Progress by Namespace

Filter progress updates by one or more namespaces:

```bash
# Single namespace
curl -X GET \
  "https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress?namespace=copilot" \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"

# Multiple namespaces
curl -X GET \
  "https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress?namespace=copilot&namespace=my-company.agent" \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"
```

### Retrieving Progress with History

Include progress from the most recent previous job in the same assignment:

```bash
curl -X GET \
  "https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress?history=true" \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"
```

This is useful for agents that need to maintain context across multiple job executions (e.g., for native SDK state continuity).

### Custom Schema Example: Claude SDK Native State

An example of a third-party progress update used by the Claude SDK integration to persist native SDK output:

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '{
    "namespace": "claude.code",
    "kind": "native",
    "version": 0,
    "content": "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"model\":\"claude-3-opus-20240229\"}"
  }'
```

This allows the Claude SDK to retrieve its native conversation history in subsequent sessions:

```bash
curl -X GET \
  "https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress?namespace=claude.code&history=true" \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"
```

## Why

Using `namespace`, `version`, and `kind` to define progress update types enables a flexible and extensible system for reporting job progress.

- **First-party progress update types** provide a standardized way for the agent implementation to utilize "system" functionality, like UI rendering of logs or errors in github.com mission control or VS Code.
- **Third-party progress update types** allow integrators to extend the system with their own custom progress history that can be interpreted by their own tools, without requiring the service to understand the payload structure.

An immediate example of a third-party progress update is used by Claude and Codex SDK integrations to persist native SDK output in the job progress history. For example, a Claude SDK integration might send progress updates with the following properties to represent native Claude SDK history required by subsequent sessions:

- **Namespace**: `claude.code` (custom integrator namespace)
- **Version**: `0`
- **Kind**: `native`

This approach ensures that:

1. The service can store and retrieve progress without understanding every possible schema
2. First-party schemas integrate seamlessly with system UIs
3. Third-party integrators have full flexibility to define custom schemas
4. Schema versioning enables evolution over time without breaking changes

*The use of `namespace`, `kind`, and `version` for broad extensibility is inspired by the [Kubernetes object format](https://kubernetes.io/docs/concepts/overview/working-with-objects/), which has been successfully adopted by other projects like [Backstage](https://backstage.io/docs/features/software-catalog/descriptor-format) to represent generic objects across external systems while still enabling "system" functionality through first-party object types.*
