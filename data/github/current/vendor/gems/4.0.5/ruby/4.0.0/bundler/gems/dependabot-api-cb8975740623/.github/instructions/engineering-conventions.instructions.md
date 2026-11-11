---
applyTo: "**"
---

# Engineering Conventions (Repo-Wide)

These conventions apply to every change in dependabot-api. They appear once here so they don't need duplication in path-specific instruction files.

## Logging & metrics correctness

Two recurring issues humans flag that Copilot has missed:

1. **Telemetry placed before early returns** fires even when nothing happens. If a log/metric call appears above a `return`/`unless`/`if-guard` that may short-circuit the work, move the telemetry below the guard or scope it to the actual code path.
2. **Metric tag values that don't match the code path** (e.g., a `cross_org` tag incremented unconditionally inside a method that only sometimes acts cross-org). Verify each tag is true at the point of emission.

Log levels:

- `error` — actually broken state that pages on-call. Not for expected contention.
- `warn` — unexpected but handled.
- `info` — normal flow.
- `debug` — developer-only detail.

If a log is added alongside a metric, ask whether it's redundant. Logs should add information the metric can't capture (specific reason, identifier, payload shape).

## Feature flags (enforced by `Dependabot/NoLocalFeatureFlags`)

Local Flipper-based feature flags are **deprecated for new code**. The `Dependabot/NoLocalFeatureFlags` RuboCop cop catches these patterns:

- `repo.config_feature_enabled?(:foo)` / `update_job.config_feature_enabled?(:foo)`
- `repo.org_level_flag_enabled?(:foo)` / `repo.repo_level_flag_enabled?(:foo)`
- `repo.enable_feature(:foo)` / `repo.disable_feature(:foo)`
- `Dependabot.flipper[:foo]`

Live code still uses these in some legacy paths with explicit `# rubocop:disable Dependabot/NoLocalFeatureFlags` annotations (e.g., `app/actions/run_updater/actions.rb`, `app/coach/routes/update_jobs/create_pull_request.rb`, `app/models/update_job.rb`). Don't flag those.

What to flag:
- A **new** call to a deprecated method without the rubocop disable comment (the cop will catch it, but call it out).
- An **expansion** of an existing suppression to cover new code added in the same PR.
- A new suppression added without an explanation in a comment or PR description.

For new gated behavior, use `monolith_feature_enabled?`. See `models.instructions.md` for the full method signatures.

## Method signature changes

When a method's signature changes (positional ↔ keyword args, renamed/added/removed parameters):

- Verify **every** call site in the diff (and via grep across the repo) is updated.
- Stubs in specs do not catch signature mismatches — look at real call sites, not just the test setup.
- For Twirp/protobuf methods, also check the proto definitions.

## Unbounded reads & writes

Database access in this codebase has size limits driven by query latency, replica lag, and Aqueduct job time budgets:

- **No unbounded reads.** Any query that could return more than ~1000 rows must be batched (`find_each`, `in_batches`, paginated cursor, or a hard `limit:` with a known bound). A `Repo.where(...)` followed by `.each` with no limit is a common bug — flag it.
- **No unbounded bulk writes.** Writes (`update_all`, `delete_all`, `insert_all`) should be bounded — typically 10-100 records per batch depending on the scope of the update and the table size. A loop that calls `update!` over an unbounded collection is also a write fan-out and should be batched the same way.
- A backfill that needs to touch many rows belongs in a transition (see `transitions.instructions.md`), not inline in app code or a migration.

## Magic numbers & shared mutable state

- Pull batch sizes, retry windows, timeouts, and limits into named constants when used in non-trivial logic.
- Avoid mutable defaults on `class_attribute` — use frozen literals (`{}.freeze`, `[].freeze`) or initialize per-instance.
- Document non-obvious constants with a comment explaining the trade-off.

## Security & secrets

- New code paths that depend on a secret (HMAC key, OAuth token, API key) must fail fast on blank/missing values — never call out with a `nil` or empty key.
- Feature flags that enable a secret-dependent code path should not be flippable to `true` until the secret is provisioned.
- Never log raw tokens, full auth headers, or webhook signing secrets. Use `<REDACTED>` placeholders or hash digests if a value must appear.
- Outbound URLs derived from user input should be parsed and validated for an expected scheme/host shape (see `app/models/registry.rb` for an example of URL-shape validation).

## Schema / example / test alignment

When changing a JSON schema, model validation, protobuf message, or factory:

- The schema, the model validation, the factory defaults, and any example/fixture payloads must all agree.
- If a JSON schema declares `additionalProperties: false`, every required key must appear in tests/examples.
- Renaming a key should propagate through code, schema, validation, factory, and tests in one PR.

## DB role safety (when applicable)

This codebase uses `ActiveRecord::Base.connected_to(role: :reading|:writing)` to route between primary and replicas in **specific subsystems** — most prominently Hydro handlers (`app/hydro/repository_push_handler.rb`) and read-only Coach routes via `Middlewares::ReadReplica`. Plenty of legitimate code paths do DB work without an explicit `connected_to` block; do not flag those.

When the diff is **inside** a `connected_to(role: :reading)` block or a route that uses `Middlewares::ReadReplica`, mutations (`update!`, `create!`, `destroy`, `delete_all`) will fail at runtime — flag them. When the diff adds new logic to a hydro handler or read-only route, verify the role boundary is preserved.
