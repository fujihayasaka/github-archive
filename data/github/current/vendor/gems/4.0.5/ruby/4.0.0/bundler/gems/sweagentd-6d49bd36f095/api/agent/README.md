# Agent API

Version: 0.1.0

## Overview

The sweagentd Agent API provides endpoints for Copilot agents to retrieve job metadata and manage progress updates during job execution. This API is designed to be called by the runtime during agent job execution.

The Agent API consists of two main capabilities:

1. **Job Retrieval**: Get the job definition, problem statement, and configuration that the agent should execute
2. **Progress Management**: Create and retrieve structured progress updates to track job execution and maintain history

For detailed information about the progress system, see the [Progress documentation](./progress/README.md).

**Base URL:** `https://api.githubcopilot.com/agent/swe`

## Authentication

All endpoints require authentication using a GitHub App installation token:

- **Type:** Bearer token (JWT)
- **Header:** `Authorization: Bearer <token>`
- **Scope:** The token must be scoped to the repository hosting the job

Additionally, most endpoints require the `X-GitHub-Job-Nonce` header for request validation.

## Endpoints

### Get Job

Retrieve the job definition that the Copilot agent should execute.

**Endpoint:** `GET /agent/jobs/{jobID}`

**Path Parameters:**

- `jobID` (required): The unique identifier for the job. Format: `{ownerID}-{repoID}-{uuid}` (e.g., `123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2`)

**Headers:**

- `Authorization` (required): Bearer token
- `X-GitHub-Job-Nonce` (required): Nonce value provided when the job was created, used to validate the request comes from the correct workflow run

**Response (200 OK):**

```json
{
  "id": "string",
  "problem_statement": {
    "content": "string"
  },
  "action": "string",
  "repository": "string",
  "server_url": "string",
  "branch_name": "string",
  "commit_login": "string",
  "commit_email": "string",
  "custom_agent": {
    "name": "string",
    "repo_owner_id": 0,
    "repo_owner": "string",
    "repo_id": 0,
    "repo_name": "string",
    "display_name": "string",
    "description": "string",
    "prompt": "string",
    "tools": ["string"],
    "version": "string",
    "mcp_servers": {},
    "infer": true,
    "model": "string",
    "handoffs": []
  },
  "available_custom_agents": [],
  "organization_custom_instructions": "string",
  "event_type": "string",
  "event_url": "string",
  "event_identifiers": ["string"],
  "agentic_app": {"metadata": {"capi_integration_id": "example-id"}}
}
```

**Error Responses:**

- `400 Bad Request`: Missing or malformed `jobID`
- `401 Unauthorized`: Authorization failed or nonce mismatch
- `404 Not Found`: Job not found or agent not enabled
- `500 Internal Server Error`: Server error

### List Job Progress

Retrieve progress entries for a job with optional filtering and history inclusion.

**Endpoint:** `GET /agent/jobs/{jobID}/progress`

**Path Parameters:**

- `jobID` (required): The unique identifier for the job

**Headers:**

- `Authorization` (required): Bearer token
- `X-GitHub-Job-Nonce` (required): Job nonce for validation

**Query Parameters:**

- `namespace` (optional): Filter progress entries by namespace. Supports multiple values via repeated parameters (`?namespace=ns1&namespace=ns2`) or comma-separated values (`?namespace=ns1,ns2`)
- `history` (optional): When true, includes progress entries from the most recent previous job for the same assignment. Accepts `"true"`, `"1"`, or `"yes"` (case-insensitive). Default: `false`
- `page` (optional): 1-based page number (reserved for future paging support). Default: `1`
- `pageSize` (optional): Page size (reserved for future paging support, max 100). Default: `50`
- `sort` (optional): Field to sort by (reserved for future paging support). Use "-" prefix for descending order. Options: `createdAt`, `-createdAt`. Default: `-createdAt`

**Response (200 OK):**

Current implementation returns a simple array:

```json
[
  {
    "id": "string",
    "namespace": "string",
    "kind": "string",
    "version": 0,
    "content": "string",
    "created_at": 0
  }
]
```

Future paginated implementation will return:

```json
{
  "items": [],
  "page": 1,
  "pageSize": 50,
  "totalCount": 0,
  "totalPages": 0,
  "hasNext": false,
  "hasPrev": false,
  "sort": "string",
  "filters": {
    "namespace": []
  }
}
```

**Error Responses:**

- `400 Bad Request`: Missing `jobID` or invalid query parameter
- `401 Unauthorized`: Authorization failed or nonce mismatch
- `404 Not Found`: Job not found
- `500 Internal Server Error`: Server error

### Create Job Progress

Create one or more progress entries for a job.

**Endpoint:** `POST /agent/jobs/{jobID}/progress`

**Path Parameters:**

- `jobID` (required): The unique identifier for the job

**Headers:**

- `Authorization` (required): Bearer token
- `X-GitHub-Job-Nonce` (required): Job nonce for validation
- `Content-Type`: `application/json`

**Request Body:**

Single progress entry:

```json
{
  "namespace": "string",
  "kind": "string",
  "version": 0,
  "content": "string"
}
```

Multiple progress entries (batch):

```json
[
  {
    "namespace": "string",
    "kind": "string",
    "version": 0,
    "content": "string"
  }
]
```

**Request Body Fields:**

- `namespace` (required): Namespace of the progress update. First-party namespaces (e.g., "copilot") map to well-known payload schemas. Third-party integrators can define custom namespaces
- `kind` (required): The kind of progress update within the namespace (e.g., "error", "log", "native")
- `version` (optional): Version of the progress update payload schema. Default: `0`
- `content` (required): JSON string payload that will be stored verbatim

**Batch Semantics:**

When an array is provided, all items are validated before any are created (all-or-nothing semantics). If any item fails validation, the entire request fails and nothing is created.

**Response (201 Created):**

Single entry response:

```json
{
  "id": "string",
  "namespace": "string",
  "kind": "string",
  "version": 0,
  "content": "string",
  "created_at": 0
}
```

Multiple entries response:

```json
[
  {
    "id": "string",
    "namespace": "string",
    "kind": "string",
    "version": 0,
    "content": "string",
    "created_at": 0
  }
]
```

**Error Responses:**

- `400 Bad Request`: Missing or malformed `jobID`, validation failure (missing fields or malformed JSON payload)
- `401 Unauthorized`: Authorization failed or nonce mismatch
- `404 Not Found`: Job not found
- `500 Internal Server Error`: Server error

## Data Models

### Job

The agent configuration and work unit that the agent will execute.

**Properties:**

- `id` (string, required): Unique identifier of the job
- `problem_statement` (object, required): The problem statement for the job
  - `content` (string, required): The problem statement or task description
- `action` (string, required): The agent action type (e.g., `fix`, `fix-pr-comment`, `task`)
- `repository` (string, required): The full repository name in `owner/repo` format
- `server_url` (string, required): The GitHub server URL (e.g., `https://github.com`)
- `branch_name` (string, optional): The branch name the agent should work on
- `commit_login` (string, required): The git author name for commits
- `commit_email` (string, required): The git author email for commits
- `custom_agent` (object, optional): Configuration for a custom agent
- `available_custom_agents` (array, optional): List of custom agents available for the job
- `organization_custom_instructions` (string, optional): Organization-wide instructions for the agent
- `event_type` (string, optional): The type of event that triggered the job (e.g., `issue_assignment`, `pull_request_comment`, `api_call_received`)
- `event_url` (string, optional): URL pointing to the triggering event
- `event_identifiers` (array of strings, optional): Identifiers for the event source (e.g., issue number, PR number)
- `agentic_app` (object, optional): Per-app data from the agentic app registry
  - `metadata` (map of string to string, optional): App-specific key-value pairs (e.g., `capi_integration_id`)

### CustomAgent

Configuration for a custom agent.

**Properties:**

- `name` (string, required): The unique name of the custom agent
- `repo_owner_id` (integer, required): The GitHub ID of the repository owner
- `repo_owner` (string, required): The name of the repository owner
- `repo_id` (integer, required): The GitHub ID of the repository
- `repo_name` (string, required): The name of the repository
- `display_name` (string, required): Human-readable display name for the agent
- `description` (string, required): Description of what the agent does
- `tools` (array, required): List of tools available to the agent
- `version` (string, required): Version of the agent configuration
- `infer` (boolean, required): Whether inference is enabled for the agent
- `prompt` (string, optional): The system prompt for the agent
- `mcp_servers` (object, optional): MCP server configurations
- `model` (string, optional): The model to use for inference
- `handoffs` (array, optional): List of suggested next actions or prompts to transition between custom agents

### CustomAgentHandoff

Handoff configuration for an agent. Handoff buttons appear as interactive suggestions after a chat response completes.

**Properties:**

- `label` (string, required): The display label for the handoff action
- `agent` (string, required): The target agent identifier to switch to
- `prompt` (string, required): The prompt to send when handing off to the new agent
- `send` (boolean, optional): Optional flag to auto-submit the handoff prompt

### McpServer

Model Context Protocol server configuration.

**Properties:**

- `type` (string): Server type such as `local`, `stdio`, `http`, or `sse`
- `tools` (array): List of tool names
- `command` (string): Command to run the MCP server (required for local/stdio servers)
- `args` (array): Arguments for the MCP server command
- `env` (object): Environment variables for the MCP server
- `url` (string): URL for remote servers (required for `http`/`sse` types)
- `headers` (object): HTTP headers for remote servers

### Progress

Represents a progress update from an agent for a job. This can be a log, status update, error, native SDK output, or any other information about the job's progress.

**Properties:**

- `id` (string, required): Unique identifier of the progress entry
- `namespace` (string, required): Namespace of the progress update
- `kind` (string, required): The kind of progress update within the namespace
- `version` (integer, required): Version of the progress update payload schema
- `content` (string, required): JSON-encoded payload captured as a UTF-8 string
- `created_at` (integer, required): Unix timestamp when the progress entry was created

The `namespace`, `version`, and `kind` properties together define the schema of the content payload, enabling polymorphic progress update types. See the [Progress documentation](./progress/README.md) for detailed information about:

- Progress object structure and field descriptions
- Well-known vs custom progress schemas
- Available schema namespaces and kinds
- Usage examples with different payload types

## Usage Examples

### Retrieve a Job

```bash
curl -X GET \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2 \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"
```

### Create Single Progress Entry

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

### Create Multiple Progress Entries

```bash
curl -X POST \
  https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>" \
  -H "Content-Type: application/json" \
  -d '[
    {
      "namespace": "claude.code",
      "kind": "native",
      "version": 0,
      "content": "{\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"model\":\"claude-3-opus-20240229\"}"
    },
    {
      "namespace": "claude.code",
      "kind": "native",
      "version": 0,
      "content": "{\"messages\":[{\"role\":\"assistant\",\"content\":\"Hi there!\"}],\"model\":\"claude-3-opus-20240229\"}"
    }
  ]'
```

### List Progress Entries with Filters

```bash
curl -X GET \
  "https://api.githubcopilot.com/agent/swe/agent/jobs/123456-654321-919774c3-fa83-4644-baf7-f02bb73821c2/progress?namespace=copilot&namespace=claude.code&history=true" \
  -H "Authorization: Bearer <token>" \
  -H "X-GitHub-Job-Nonce: <nonce>"
```

## Notes

- The `page`, `pageSize`, and `sort` parameters on the list progress endpoint are reserved for upcoming pagination support
- Progress entries support both first-party (service-defined) and third-party (integrator-defined) namespaces
- All timestamps are Unix timestamps (seconds since epoch)
- The `content` field in progress entries must be a valid JSON string
