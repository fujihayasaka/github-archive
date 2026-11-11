---
applyTo: "app/jobs/**/*.rb"
---

# Background Jobs Code Review Rules

Jobs inherit from `ApplicationJob < ActiveJob::Base` (`app/jobs/application_job.rb`). Aqueduct provides the worker infrastructure. Reference: `app/jobs/setup_repo_job.rb`, `app/jobs/update_pull_request_job.rb`, `app/jobs/scheduled_jobs/`.

## Backwards-compatible job arguments

Job argument signatures must change in a backwards-compatible way. Aqueduct serializes job arguments at enqueue time, and during a rolling deploy old-code pods enqueue jobs that new-code pods will dequeue (and vice versa). A breaking signature change drops or fails in-flight jobs.

Common breaking changes to flag:

- Adding a new positional or keyword argument to `perform` **without a default value** (e.g., `def perform(foo:, bar:)` when `bar:` is new). Provide a default (`bar: nil`) and gate behavior on it.
- Removing or renaming an existing argument. Add the new arg with a default first; deprecate and remove the old arg in a follow-up deploy.
- Changing an argument's type/shape (e.g., a positional ID becoming a hash). Same multi-deploy migration: accept both shapes, switch enqueuers, then drop the old shape.

Tests stub `.perform_later`, so they do not catch arg-signature breaks against in-flight serialized jobs — verify the change against an existing-arg call site, and consider whether queued jobs at deploy time would still work.

## Job duration & batching

Aqueduct workers are killed during k8s pod shutdowns on deploy. The hard ceiling is ~5 minutes; the practical target is **under 1 minute** so a job has headroom if it runs long and so it doesn't tie up a worker for too long. Some existing jobs run longer — that's tolerated, not encouraged.

When a job iterates over a potentially-large collection or calls slow upstream APIs:

- Prefer `TimedJob` (`app/jobs/timed_job.rb`) — it processes a batch within a time budget and re-enqueues itself for the next batch (see `app/jobs/scheduled_jobs/delete_old_update_jobs_data.rb`, `app/jobs/scheduled_jobs/enqueue_scheduled_update_jobs.rb`).
- Or implement custom batching: process N items, enqueue a follow-up for the next batch, exit.
- A new job that does an unbounded `find_each` over a hot table is a red flag — request batching or a `TimedJob` rewrite.

(Read/write batch size guidance is in `engineering-conventions.instructions.md`.)

## Idempotency (HIGHEST PRIORITY)

Jobs **must** be safe to retry. Re-running the same job must not:

- Create duplicate database records (use `find_or_create_by!`, unique constraints, or check-then-act with locks).
- Send duplicate notifications, comments, or external API calls without de-duplication.
- Accumulate counters or trigger duplicate side effects.

If a new job is not idempotent, request a justification or a redesign.

## Retry helpers

`ApplicationJob` provides composite retry helpers. Use them as bare class-level macros — don't wrap them around `perform`:

```ruby
class MyJob < ApplicationJob
  queue_as :default
  default_retries_for_idempotent_jobs

  def perform(...)
    # ...
  end
end
```

`default_retries_for_idempotent_jobs` is the composite of:

- `retry_on_dirty_exit` — `Aqueduct::Worker::JobKilled`
- `retry_on_recoverable_database_exceptions`
- `retry_on_recoverable_aqueduct_exceptions`
- `retry_on_recoverable_redis_exceptions`
- `retry_on_restraint_unable_to_lock`
- `retry_on_throttler_timeout`

Use one of the more specific helpers if `default_retries_for_idempotent_jobs` is too broad. **Do not** use `retry_on Exception` or `retry_on StandardError` — that masks real bugs.

## Retry math

When configuring retries with a TTL (e.g., "retry for 20 minutes"), verify the math:

```ruby
attempts = job_retry_ttl / wait
```

Make sure `wait * attempts >= intended_window`. Off-by-one or rounding errors are common — surface them in review.

## Structure

- `perform(...)` is the entrypoint. Keep its body small; extract to private methods or actions.
- Use `queue_as :name` — pick the appropriate queue for the workload.
- Use `rescue_from SpecificError do |e| ... end` for class-wide error handling. A broad `rescue_from StandardError` is acceptable for terminal cleanup/telemetry/re-raise patterns (see `app/jobs/generate_pull_request_autofix_job.rb`); for other handling, prefer specific exception classes.

## Logging & metrics

- `ApplicationJob` automatically wraps `perform` with `Dependabot::Logger.log_context(...)` and instruments errors via `MetricsClient.increment("job.failed", ...)`. You don't need to re-implement these.
- Add job-specific metrics with `MetricsClient.increment` / `.distribution_time`. Tag values must be low-cardinality (job name, queue, error class — not record IDs).

(General log-level discipline and telemetry-vs-early-return rules are in `engineering-conventions.instructions.md`.)

## Class attributes

- Avoid mutable defaults on `class_attribute` (e.g., `class_attribute :foo, default: []` or `default: {}`). Subclasses share the same instance and can mutate cross-job state. Either use an immutable frozen default (`default: {}.freeze`, `default: [].freeze`, as in `app/jobs/timed_job.rb`) and reassign instead of mutating, or initialize fresh state per instance.

## GitHub API access

When a job calls the GitHub API:

- Prefer `GitHubHelpers::ClientWithRetries.new(account: ..., repo_ids: ..., permissions: ...)` over instantiating `Octokit::Client` directly. It handles tenancy headers, HMAC, retries, and access-token caching.
- For paginated list endpoints, use `GitHubHelpers.fetch_all_pages(client:, method:, args:, max_pages:)` rather than rolling your own page loop. Pass `max_pages` when there's a sensible bound; an unbounded fetch on a large account can be expensive.
- When retrying on `Octokit::Unauthorized`, **invalidate the cached installation token before the retry**. The pattern in `app/jobs/update_pull_request_job.rb`, `app/jobs/cancel_actions_workflow_run_job.rb`, and `app/jobs/after_unpause_repo_job.rb` is to delete the cached access token via `GitHubHelpers.delete_cached_access_token_for(account: ...)` and clear the memoized client. A bare `retry_on Octokit::Unauthorized` without cache invalidation will keep using the same expired token.

## Constants over magic numbers

- Pull batch sizes, timeouts, and retry windows out as named constants. See `engineering-conventions.instructions.md` for the general rule.

## Reviewer checklist

- Job is idempotent (or has explicit justification).
- New or changed `perform` arguments are backwards-compatible (defaults on new args; multi-deploy migration for renames/removals).
- Long-running or large-iteration work uses `TimedJob` or explicit batching+requeue (target <1m, max ~5m).
- Uses `default_retries_for_idempotent_jobs` or a specific subset, not blanket `retry_on`.
- Telemetry fires only on the actually-described code path.
- `rescue_from` uses specific exception classes (broad `StandardError` is OK for terminal cleanup only).
- Tests cover both success and failure paths, with assertions on enqueued follow-ups and metrics.
