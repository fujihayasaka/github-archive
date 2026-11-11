# Progress API Namespace Conventions for Code Review

Status: proposed

Deciders: @arthurnn @colbylwilliams @josebalius @c0deking @rasmuswl @aeisenberg

Related issue: Code Review Agent platform architecture

## Context

The sweagentd Progress API (`POST /jobs/{jobID}/progress`) is a polymorphic event pipeline where `namespace`, `kind`, and `version` define the schema of each progress update. Multiple products need to publish review findings through this pipeline:

- **CCR (Copilot Code Review)** — autofind results consumed by CCRA
- **3P code review engines** — findings from third-party agents (Claude, Codex, etc.)
- **Code Scanning** — security detections consumed by Turboscan

### Current status

- Each engine already uses its own namespace for session history (`claude-agent`, `copilot`, etc.)
- `sessions-v2` is the platform namespace with side-effects (PR comments, summaries)
- `code-review` is already registered as a known namespace in `internal/integrations/codereview/codereview.go`
- `agent_id` (= Integration ID of the AgenticApp) is already present on every `JobProgress` Hydro event (`emitter.go:54`)

### Requirements

- Adding a new namespace requires a sweagentd code change + deploy (checked via `IsProgressNamespace()`)
- Adding a new `kind` requires no sweagentd changes — consumers own kind interpretation
- Unregistered namespaces are stored in Cosmos but **not emitted as Hydro events** (`emitProgressEvent` returns on `default` case)
- Anyone with a valid job token can call the Progress API — namespace alone doesn't provide access control

## Alternatives considered

### Per-engine namespaces (`claude-code-review`, `codex-code-review`, etc.)

Rejected because:
- Requires a sweagentd deploy every time a new engine does code review
- Creates namespace proliferation with no clear benefit
- Consumers would need to handle N namespaces instead of filtering by `kind` + `agent_id`

### Everything in `sessions-v2`

Rejected because `sessions-v2` has existing side-effects (PR comments, summaries) managed by the platform. Code review findings have different consumers and lifecycle. Mixing them would couple unrelated concerns.

### Separate 1P-only namespaces for CCR

The initial proposal was to isolate CCR into a 1P-only namespace. Rejected because the Progress API is accessible to anyone with a valid job token — namespace doesn't provide access control. `agent_id` on the `Job` (set by sweagentd from the job record) is the correct identity signal.

## Decision

### One shared namespace for all code review findings: `code-review`

All code review findings — from CCR (autofind) and 3P engines — use `namespace: "code-review"`. The `kind` field distinguishes payload types:

| Producer | Namespace | Kind | Consumer |
|----------|-----------|------|----------|
| Autofind (CCR) | `code-review` | `ccr:review-results` | CCRA |
| 3P engines (via `submit_review_comment` tool) | `code-review` | `finding` | GitHub monolith |

### `agent_id` for identity, not namespace

Consumers distinguish **who** sent a finding via `job.agent_id`, which maps to the **Integration ID** of the AgenticApp that owns the job.

- **CCR / 1P:** CCRA knows its own Integration ID and filters to only its own `agent_id`.
- **3P:** GitHub (gh/gh) holds the registry of AgenticApps that support code review. The 3P consumer filters by `agent_id` against this registry.

### Code Scanning gets its own namespace

Code Scanning is a distinct product with its own service, consumers, and lifecycle. A separate namespace (e.g., `code-scanning-security`) lets each product team own their routing independently.

| Producer | Namespace | Kind | Consumer |
|----------|-----------|------|----------|
| Code Scanning | `code-scanning-security` | `review-results` | Code Scanning (Turboscan) |

### Session logs remain separate

Engines continue to use `sessions-v2` for session UI / Mission Control logs, and their own namespace for engine-specific history. Code review findings are a **separate concern** — the same engine run may emit both.

## Implications

- **`code-review` namespace is already registered** — no sweagentd change needed for CCR or 3P code review findings.
- **Code Scanning namespace is now registered** — `code-scanning-security` in `internal/integrations/codescanning/codescanning.go`.
- **New 3P engines are zero-cost** — they emit `namespace: "code-review"`, `kind: "finding"` with no sweagentd or consumer changes.
- **Identity is platform-enforced** — `agent_id` comes from the `Job` record, not from the caller. Engines cannot spoof it.
- **Consumers filter by namespace + `agent_id`** — CCRA consumes `code-review` messages for its own agent ID; 3P consumer does the same against the AgenticApp registry.
