# First-Party Integration Progress Namespaces

This guide is for **first-party GitHub teams** that want to emit `JobProgress` events through sweagentd for their integration. It explains how the progress emission system works, and how to register a new namespace so that sweagentd propagates your progress events to downstream consumers (e.g., Mission Control).

## Background

The progress API allows agents to stream incremental updates during job execution. These updates are stored in the database and can be retrieved by the agent in future sessions.

For a subset of _well-known_ namespaces, sweagentd also **emits `JobProgress` Hydro events** so that downstream systems (Mission Control, VS Code, etc.) can react to progress in real time. This document covers how to get your namespace onto that emit list.

### Design Principles

1. **sweagentd is namespace-agnostic** — sweagentd does not parse, validate, or transform your progress payloads. It passes them through as-is. Your consumer is responsible for interpreting `kind`, `version`, and the `content` payload.

2. **One umbrella namespace per integration** — Choose a single top-level namespace that can serve as an umbrella for all your current and future progress types. Use `kind` and `version` to differentiate within your namespace. This way sweagentd never needs to change as you iterate.

3. **Consumers filter by namespace** — Downstream consumers (like Mission Control) should opt-in to only the namespaces they care about, rather than filtering out namespaces they don't recognize. This prevents breakage when new namespaces are added.

## How It Works

When an agent calls `POST /agent/jobs/{jobID}/progress`, sweagentd:

1. **Stores** the progress update(s) in the database (all namespaces).
2. **Emits a `JobProgress` Hydro event** if the namespace is on the emit list.

The emit list is defined in [`internal/integrations/`](../../../internal/integrations/). Integrator namespaces are emitted **unconditionally** (not gated by `UseAsyncSessions`), unlike the legacy session namespaces which are gated.

## Adding a New Namespace

### Step 1: Create an integration package

Create a new package under `internal/integrations/` for your integration:

```
internal/integrations/
├── integrations.go           # Aggregates all integration namespaces
├── codereview/
│   └── codereview.go         # Code Review integration
└── yourintegration/
    └── yourintegration.go    # Your integration
```

Your package should define a `ProgressNamespace` constant:

```go
// Package yourintegration provides details about the Your Integration integration.
package yourintegration

// ProgressNamespace is the namespace used for progress updates
// from the Your Integration integration.
const ProgressNamespace = "your-namespace"
```

### Step 2: Register in the integrations package

Add your namespace to the `progressNamespaces` slice in `internal/integrations/integrations.go`:

```go
package integrations

import (
    "slices"

    "github.com/github/sweagentd/internal/integrations/codereview"
    "github.com/github/sweagentd/internal/integrations/yourintegration"
)

var progressNamespaces = []string{
    codereview.ProgressNamespace,
    yourintegration.ProgressNamespace,
}

func IsProgressNamespace(ns string) bool {
    return slices.Contains(progressNamespaces, ns)
}
```

That's it for the sweagentd side. No other code changes are needed — the emission logic in `internal/agent/service.go` dynamically checks `integrations.IsProgressNamespace()`.

### Step 3: Add tests

Run the existing tests to confirm nothing breaks:

```bash
go test ./internal/agent/... -count=1
```

The test suite in `internal/agent/service_test.go` validates the emission behavior for integrator namespaces.

## Choosing a Namespace

| Guideline | Example |
|-----------|---------|
| Use a descriptive, kebab-case name | `code-review` |
| Scope it broadly enough for future needs | Don't use `code-review-poc` |
| Use `kind` for sub-types | `kind: "review-status"`, `kind: "suggestion"` |
| Use `version` for schema evolution | `version: 0` → `version: 1` |

**Avoid** creating multiple namespaces for the same integration. One umbrella namespace keeps the emit list small and means sweagentd never needs to change as you add new progress types.

## What Gets Emitted

For integrator namespaces, sweagentd emits a `JobProgress` Hydro event with the following data passed through from your progress update:

| Field | Source |
|-------|--------|
| `namespace` | Your namespace (as-is) |
| `kind` | Your kind (as-is) |
| `version` | Your version (as string) |
| `content` | Your content payload (JSON-serialized, as-is) |
| `created_at` | Timestamp from the stored progress entry |

The Hydro event also includes full job metadata (job ID, assignment ID, repository, actor, etc.).

## Important Notes

- **No content validation** — sweagentd does not validate your `content` payload. Your consumer must handle malformed content gracefully.
- **No sender verification (yet)** — Currently, any agent running a job can send progress with any namespace. Your consumer should account for the possibility of receiving events that didn't come from your integration. We plan to add sender identity verification in the future.
- **Mission Control consumers** should subscribe to only the namespaces they care about (opt-in), not filter out unknown ones (opt-out). This is critical for forward compatibility.

## Current Integrations

| Namespace | Integration | Package |
|-----------|-------------|---------|
| `code-review` | Copilot Code Review | `internal/integrations/codereview` |

## Related Documentation

- [Progress System Overview](./README.md) — Full progress API documentation
- [Well-Known Schemas](./copilot/README.md) — First-party `copilot` namespace schemas
- [Agent API Reference](../README.md) — Agent API endpoints
