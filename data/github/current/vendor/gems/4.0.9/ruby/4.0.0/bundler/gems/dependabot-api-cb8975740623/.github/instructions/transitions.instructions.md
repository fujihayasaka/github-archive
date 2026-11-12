---
applyTo: "lib/dependabot/transitions/**/*.rb,spec/lib/dependabot/transitions/**/*.rb"
---

# Data Transitions Code Review Rules

Transitions are scripts that perform data backfills, repairs, or one-off mutations in production. They live at `lib/dependabot/transitions/` and follow a strict pattern enforced by the base class `Dependabot::Transition` (`lib/dependabot/transition.rb`).

Reference transitions to model after:
- `lib/dependabot/transitions/20251230042641_backfill_current_state_values.rb` — large multi-table backfill with batching, throttling, and Sorbet sigs
- `lib/dependabot/transitions/20260114210000_backfill_security_updates_incident.rb` — incident-driven backfill from a fixed list of repo IDs
- `lib/dependabot/transitions/20251118175050_retry_actions_workflow_failed_jobs.rb` — targeted job retry

Related external docs (in `github/dependabot-updates`):
- `docs/operating-manual/incident-repair.md` — when transitions are appropriate vs. chatops
- `docs/operating-manual/on-call.md` — running transitions during incidents
- `docs/managing-dependabot-apps.md` — transition examples

## Required structure

A new transition must:

1. **Live at `lib/dependabot/transitions/<timestamp>_<snake_name>.rb`** with a matching `_spec.rb` under `spec/lib/dependabot/transitions/`. The timestamp follows the migration timestamp format (`YYYYMMDDHHMMSS`).
2. **Inherit from `Dependabot::Transition`** and implement `perform` (not `run` — `run` is the base-class driver).
3. **Begin with the standard preamble** (see existing transitions):
   ```ruby
   # frozen_string_literal: true

   require_relative "../../../config/environment"
   require "slop"
   require "dependabot/transition"
   ```
4. **Document how to run it** in a top-of-file comment, including:
   - The chatops command (e.g., `.transitions run <pr-url> <environment> <filename> -v`) **or** the direct `gh-k8s-shell` invocation when chatops isn't available
   - Both dry-run and write-mode invocations (`-v` for verbose, `-w` for write)
   - Whether deployments need to be locked beforehand
   - Which environment(s) it targets (specific stamp like `prod-weu-01` or `*` for all)

## Safety invariants (CRITICAL)

The base class defaults `dry_run: true` and routes to the read-only MySQL connection in dry-run mode. New transitions must preserve these invariants:

- **Idempotency**: re-running the transition must not double-apply changes. Use scoped queries that exclude already-processed records (e.g., `where(current_state: nil)`).
- **Resumability**: the transition must be safe to resume after a crash. Process records in batches and don't keep critical progress in memory only.
- **Dry-run safety**: in `dry_run?`, the transition must not write. Guard mutations with `return if dry_run?` or only call write methods inside `unless dry_run?`. **Test the dry-run path** in the spec.
- **Bounded scope**: prefer a fixed input set (a file of repo IDs, a `where` filter) over an open-ended scan. Cite the source of the bound in a comment (e.g., a Kusto query, an audit-log dump).

## Throttling and batching

Production transitions that write to MySQL must throttle via Freno:

```ruby
FRENO_CLUSTER = :dependabot

Dependabot.freno_throttler.throttle(FRENO_CLUSTER) do
  record_type.where(id: batch_ids, current_state: nil).update_all(current_state: ...)
end
```

- Define `READ_BATCH_SIZE` and `WRITE_BATCH_SIZE` constants (typical: 1000 reads, 100 writes — see `20251230042641_backfill_current_state_values.rb`).
- Wrap throttled blocks in a retry on `Freno::Throttler::Error` and `Dependabot::Exceptions::RECOVERABLE_DATABASE_EXCEPTION_CLASSES` with bounded retry count.
- Use `process_batches` / `in_batches` rather than `find_each` for write-heavy work — batched `update_all` is far cheaper than per-record callbacks.

## Companion migrations

When a transition supports a schema change, the migration should reference the transition file (see `db/migrate/20260118191643_run_current_state_backfill_on_ghes.rb` which calls `Dependabot::Transitions::BackfillCurrentStateValues.new(dry_run: false).perform`). Verify:

- The transition file exists and the `require_relative` path is correct.
- The migration only runs the transition in the appropriate environment (`return unless Dependabot.enterprise?` is the common pattern, since cloud runs the transition out-of-band via chatops).

## Testing

Each transition needs a spec under `spec/lib/dependabot/transitions/` that covers:

- **Dry-run mode does not write** — assert no records change when `dry_run: true`.
- **Write mode applies the change idempotently** — run the transition twice; assert the second run is a no-op.
- **Freno throttler is invoked** — stub `Dependabot.freno_throttler` to yield and assert the throttled block ran.
- **Verbose mode does not raise** — at minimum, instantiate with `verbose: true` and run.

Reference: `spec/lib/dependabot/transitions/20251230042641_backfill_current_state_values_spec.rb`.

## Reviewer checklist

- File lives at `lib/dependabot/transitions/<timestamp>_<name>.rb` and inherits from `Dependabot::Transition`.
- Top-of-file comment documents both dry-run and write-mode invocations (chatops or `gh-k8s-shell`).
- `perform` (not `run`) is the implementation hook.
- Mutations are guarded by `dry_run?` and throttled via `Dependabot.freno_throttler`.
- Bounded scope: the set of records being processed is explicitly limited (file, fixed query, count).
- Spec covers dry-run, write, and idempotency.
- Companion migration (if any) references the transition with a correct `require_relative` path and is environment-scoped.
