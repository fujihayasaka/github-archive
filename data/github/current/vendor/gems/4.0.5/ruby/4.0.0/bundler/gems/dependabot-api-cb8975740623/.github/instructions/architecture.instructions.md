---
applyTo: "**"
---

# Architecture & Code Flow (Repo-Wide)

This file gives the mental model of how dependabot-api fits together so a review of one part can spot when a change collides with another. Subsystem-specific rules live in the dedicated `*.instructions.md` files.

## Entry points

Five ways work enters the system:

1. **Coach HTTP routes** (`app/coach/`) — gh.com webhooks, dotcom UI, internal endpoints. See `coach-routes.instructions.md`.
2. **Twirp RPC** (`app/services/`) — internal service-to-service calls, wrapped by `Services::RackApp` (HMAC auth, metrics). See `services.instructions.md`.
3. **Hydro events** (`app/processors/` → `app/hydro/`) — async events from gh.com (push, repo deleted, vulnerability alerts). See `hydro-processors.instructions.md`.
4. **Scheduled jobs** (`app/jobs/scheduled_jobs/`) — periodic work. They include `ActiveJob::ScheduledJob::Base` (sometimes via `ApplicationScheduledJob`, sometimes via a `TimedJob` subclass — both are valid).
5. **ChatOps controller** (`app/controllers/chatops_controller.rb`) — operator-driven Hubot commands. This is a normal Rails controller, **not** a Coach route.

## Canonical work flow

Most production changes ride this pipeline:

```
Entry point  →  Action  →  Job (often)  →  Model + State Machine
```

- Coach routes and Twirp handlers should be **thin** — validate, look up, then call an action or `perform_later` a job. Bounded inline orchestration is accepted (e.g., `app/services/update_configs_service/v1/handler.rb`); deep business logic is not.
- Hydro handlers **guard early**, do bounded inline work (often inside `connected_to(role: :reading|:writing)` blocks), and enqueue jobs for anything heavier than ~hundreds of ms.
- **Actions** (`app/actions/`) hold sync business logic (`run` entrypoint). Most state transitions are triggered from actions, not jobs.
- **Jobs** (`app/jobs/`) do async, **idempotent** work. Many are thin shells around an action (see `DeactivateRepoJob` calling `DeactivateRepo`).
- **State changes go through Statesman**: `model.transition_to(:state)` / `transition_to!`. `before_transition` and `after_transition` callbacks fire side effects (logs, metrics, follow-up jobs). **Never** bypass with `update!(state: ...)` — that skips guards and callbacks.
- Models occasionally enqueue jobs directly for clearly-scoped operations (e.g., `Repo#pause!`, `UpdateJob#retry!`). That's accepted; flag it only when it adds a circular dependency.

## Two real flows worth memorizing

### Repository "deleted" webhook

```
gh.com webhook
  → app/coach/routes/github_webhooks/create.rb               (parse & dispatch)
  → app/actions/handle_webhook/repository.rb#run             (action)
       ├─ "deleted"/"archived" → DeactivateRepoJob.perform_later
  → app/jobs/deactivate_repo_job.rb#perform
  → app/actions/deactivate_repo.rb#run
       └─ each active update_config: config.transition_to(:deleted, ...)
  → app/state_machines/update_config_state_machine.rb        (after_transition: logs, metrics)
```

Note: it's `UpdateConfig` that transitions to `:deleted`, **not** the `Repo`.

### Hydro repository-push

```
Kafka topic github.v1.RepositoryPush
  → app/processors/repository_push_processor.rb              (handle_topic)
  → app/hydro/repository_push_handler.rb#run
       ├─ connected_to(role: :reading)  → look up repo, decide what to do
       ├─ connected_to(role: :writing)  → small inline updates
       ├─ enqueue UpdatePullRequestCiStatusJob               (per-PR work)
       └─ enqueue CheckPullRequestForConflictsJob            (per-PR work)
```

Handlers can do bounded inline DB work; fan-out and slow ops go to jobs.

## Schema change with a backfill

The current_state rollout is the recent reference (`db/migrate/20251230035147_add_current_states.rb`, `lib/dependabot/transitions/20251230042641_backfill_current_state_values.rb`, `db/migrate/20260118191643_run_current_state_backfill_on_ghes.rb`):

1. Additive migration to add the column.
2. Separate transition under `lib/dependabot/transitions/` to backfill.
3. For cloud, run the transition out-of-band via `.transitions` chatops. For GHES (single-tenant), invoke the transition from a follow-up migration scoped to `Dependabot.enterprise?`.

See `migrations.instructions.md` and `transitions.instructions.md`. Some older migrations run the transition inline (`db/migrate/20220816085703_*`); both shapes exist.

## When reviewing a change, ask:

- **Which ingresses can reach this code?** Coach, Twirp, Hydro, scheduled job, ChatOps? A change in a model or action may need to be safe under all of them.
- **If this changes a `Repo` / `UpdateConfig` / `UpdateJob` / `PullRequest` field or state, what callbacks and downstream jobs read it next?** A new column or transition often has implicit consumers in `after_transition` callbacks and scheduled jobs.
- **If this enqueues work, is the retry path safe?** `perform_later` may be retried — the job and any action it calls must be idempotent.
- **Did the work land in the right layer?** Heavy work in a coach handler, business logic in a model, or unbounded fan-out in a hydro handler are common misplacements.
- **Are state changes going through Statesman?** A direct `update!(state: ...)` bypasses guards and `after_transition` callbacks — flag it.
- **Does telemetry sit where the work actually happens?** A metric in a coach handler that describes work done in a downstream job will be misleading.
