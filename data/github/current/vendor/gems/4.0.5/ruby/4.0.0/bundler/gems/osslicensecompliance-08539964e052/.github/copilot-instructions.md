# Copilot Instructions for osslicensecompliance

## Build, Test, and Lint

```bash
# Build all binaries
make build

# Run all tests (with race detector)
make test
# equivalently: go test -race ./...

# Run tests for a specific package
go test ./internal/evaluator/...

# Run a single test by name
go test ./internal/evaluator/... -run TestPolicyResultForPackage -count=1

# Lint (uses golangci-lint via github/go-linter)
make lint

# Lint only PR-changed files
make lintpr

# Format code (prints changed files)
make fmt

# Buf proto linting + breaking change detection
make lintbuf
```

## Architecture

This is a Go service implementing **license compliance for GitHub's dependency graph**. It evaluates whether a repository's dependencies comply with enterprise/organization/repo-level license policies.

### Entry Points (`cmd/`)

- **`twirp`** — Primary Twirp RPC server (port 8080). Handles policy CRUD, compliance checks, and alert management.
- **`snapshot-processed`** — Kafka consumer that triggers compliance checks when dependency snapshots complete.
- **`transitions`** — CLI tool for database migrations/backfills with pluggable transition functions.
- **`chatops`** — ChatOps RPC service for Slack integration.
- **`codespace-cli`**, **`twirp-test`**, **`chatops-test`**, **`check-deletion-cycle`** — Dev/test utilities.

### Core Packages (`internal/`)

- **`application`** — DI container. Creates `Subsystems` holding storage, API clients, and event publishers. Supports "real" mode (MySQL + Azure + Kafka) and "null" mode (SQLite + stubs) for dev/test.
- **`twirp`** — Twirp service handlers implementing the `LicenseCompliance` RPC interface. Split across `crud.go`, `check.go`, `alert.go`, `support.go`, etc.
- **`storage`** — Data access layer. Uses MySQL for alerts/check jobs, Azure Blob Storage for policy protobuf blobs (with ETag-based optimistic concurrency via `Swap()`), and SQLite for dev/test.
- **`evaluator`** — Core compliance engine. Evaluates packages against a `CompletePolicy` (enterprise → org → repo hierarchy). Handles SPDX license expressions and distribution contexts.
- **`policy`** — Policy mutation logic with async event publishing.
- **`models`** — Domain wrappers around protobuf types (`CompletePolicy`, `Package`).
- **`consumer`** — Kafka/Hydro consumer for `SnapshotProcessed` events.
- **`repocheck`** — Orchestrates end-to-end repository compliance checks.
- **`transitions`** — Registry of named transition functions for data migrations.

### Proto & Generated Code

- **`proto/`** — Protobuf source files.
- **`pkg/proto/v0/`** — Generated Go Twirp stubs.
- **`ruby/`** — Generated Ruby Twirp client (published as `osslicensecompliance-client` gem).
- **`hydroproto/`** — Generated protobuf for Hydro domain events (alert status changes, policy changes).

To regenerate proto code after modifying `.proto` files:

```bash
# Regenerate Go and Ruby code from proto files (requires Docker)
make protoc
```

**Note:** When adding new RPCs, update the VERSION file (`proto/oss_license_compliance/v0/VERSION`) to bump the minor version before running `make protoc`.

### Data Storage

- **MySQL** — Alerts, alert events, check jobs, sequences. Schema managed by Skeema in `schemas/`.
- **Azure Blob Storage** — Policy protobufs stored by entity type + ID. Optimistic concurrency via ETag-based `Swap()`.
- **SQLite** — In-memory replacement used in dev mode (`SUBSYSTEMS=null`) and tests.

## Key Conventions

### Functional Options Pattern

Storage query/update functions use functional options (`With*` functions):

```go
storage.UpdateAlertStatusWithEvent(ctx, alertID, newStatus,
    WithEventBody("reason"),
    WithEventUserID(userID),
    WithAlertHooks(hooks),
)
```

### Testing Patterns

- **Testify** (`assert`/`require`) for assertions, not raw `if` checks.
- **Table-driven tests** for parameterized cases.
- **`newTestServer(t)`** creates a server with null subsystems for Twirp handler tests.
- **`application.NewNullApplication()`** bootstraps an app with SQLite + stubs for integration tests.
- **`testing/synctest`** for testing time-dependent and async code. Within `synctest.Test()`, `time.Now()` returns a fixed time (`2000-01-01 00:00:00 UTC`) and goroutines can be synchronized with `synctest.Wait()`. Use this instead of ignoring timestamps or adding arbitrary sleeps.
- **Testcontainers** for MySQL integration tests (requires Docker).

### Application Bootstrap

All services follow: load config → init telemetry → create `Application` with `Subsystems` → run service → graceful shutdown. Dev mode is activated with `HEAVEN_DEPLOYED_ENV=development SUBSYSTEMS=null`.

### Error Handling

- Standard Go error wrapping with `fmt.Errorf("...%w", err)`.
- Twirp framework errors in RPC handlers.
- `ValidationError` in `repocheck` for domain validation.

#### Sentry Grouping

Errors are reported via the `go-server` reporter (Failbotg → Sentry in prod, logs in dev).

Two separate concerns:

- **Issue grouping** — Sentry hashes the stack trace at the `Report(...)` call site (`go-exceptions/stacktracers/pkgerrors`). Message text does **not** affect grouping.
- **Issue title** — Sentry uses the full rendered error chain (`exception.Error()`) as the displayed title. Every `fmt.Errorf` wrapper in the chain contributes. Dynamic content here doesn't split issues, but it makes triage and alerting painful.

Rules when wrapping errors anywhere in the chain:

- **Never interpolate entity IDs (`%d`, `%v`) into wrapper messages.** The title that on-call sees should be the same regardless of which repo/org/user triggered it.
- **Stable enums are fine.** A fixed set of values (policy level, container name, status) keeps the title cardinality bounded and is still readable.
- **Use stable prefixes** and wrap the underlying cause with `%w`. The wrapped cause (Azure URL, MySQL message) carries the ID anyway, so no information is lost.
- **Per-request IDs belong in customfields, not titles:**
  - In Twirp RPCs, `internal/twirp/customfields_interceptor.go` automatically copies request fields onto `customfields` (tags for `repository_id` / `organization_id` / `enterprise_id` / `user_id`; fields for the rest).
  - In the Kafka consumer, `processMessage` + `HandleSnapshotProcessed` in `internal/consumer/consumer.go` do the same for `repository_id`, `commit_sha`, `detector_name`.
  - For new entrypoints, install `requestcache.WithEmptyCache(ctx)` + `reporter.WithReporter(ctx, r)` and call `customfields.AddTag` / `customfields.AddField` near the top of the handler.

```go
// BAD — IDs in the title; on-call sees N noisy variants of the same bug
return fmt.Errorf("failed to read repo policy id: %d: %w", repoID, err)

// BAD — even one layer up, IDs still land in the rendered chain
return fmt.Errorf("check repository %d: %w", repoID, callErr)

// GOOD — stable title; ID surfaces via customfields tag + wrapped cause
return fmt.Errorf("failed to read repo policy: %w", err)

// GOOD — stable enum keeps title cardinality bounded (≤ 3 variants)
return fmt.Errorf("failed to run update on %s policy: %w", level.String(), err)
```

#### Logging vs Reporting

Sentry (via the reporter) and Splunk (via the logger) are different sinks. Don't log the same error twice — and don't silently drop errors that never reach Sentry.

Rules:

- **In a Twirp RPC handler that returns an error**: don't call `logger.Error(...)` before `return`. `loggingHook` already logs the request at error level (with cause) and `errorReporterHook` already reports to Sentry. Explicit logs at this layer are pure duplication.
- **In a helper that returns its error to a caller**: don't log there either. The site that finally swallows or returns to a framework boundary is the one place that should log/report.
- **At a boundary where the error is swallowed (returns `nil` or never propagates)**: log with `logger.Error` AND call `reporter.Report(ctx, err, nil)` / `reporter.ReportWithValues(ctx, err, payload)`. Without the report, Sentry never sees it.
- **In a detached goroutine spawned from an RPC**: Twirp hooks do not fire on the new goroutine. Treat it as a swallow site — log and report. See `internal/twirp/check.go` and `internal/twirp/support.go` for the pattern.
- **Validation / bad-input errors deliberately swallowed**: log only. Don't report — they would create Sentry noise for caller bugs we can't fix.

### Local Development

```bash
# Null mode (in-memory, no external dependencies)
make null-twirp-api

# Codespace mode (SQLite + null subsystems on port 9599)
make gh-codespace-server

# Seed test alerts
make gh-codespace-seed

# Full local mode (requires VPN + Docker services)
docker compose up  # starts MySQL, Azurite, Redis, Kafka
DEPENDENCY_GRAPH_HMAC_KEY=<key> go run cmd/twirp/main.go
```
