---
applyTo: "app/actions/**/*.rb"
---

# Actions Code Review Rules

Actions encapsulate business logic as small, single-responsibility classes invoked via a `run` method. Examples: `app/actions/create_comment.rb`, `app/actions/handle_webhook/repository.rb`, `app/actions/run_updater/actions.rb`.

## Structure

- The public entrypoint is `run` (no arguments). Constructor parameters carry the inputs.
- Keep actions focused on a single responsibility. If an action grows large, propose splitting it or delegating to other actions/jobs.
- Private helpers are preferred over inline logic in `run`.

## Logging

- Use `Dependabot::Logger.info`/`.warn`/`.error` with a `msg:` keyword and structured context fields, not positional strings.
- Wrap units of work in `Dependabot::Logger.log_context(context_hash) do ... end` to attach context to every log line within the block (see `app/actions/handle_webhook/repository.rb`).
- Use OpenTelemetry-style keys for context fields: `"code.namespace"`, `"gh.repo.id"`, `"gh.owner.id"`, `"gh.installation.id"`, `"messaging.active_job.executions"`, etc.

(General log-level discipline and telemetry-vs-early-return rules are in `engineering-conventions.instructions.md`.)

## Error handling

- Prefer specific rescues (`Octokit::NotFound`, `Octokit::Forbidden`, `ActiveRecord::RecordNotFound`) over `rescue StandardError`.
- Do not silently swallow exceptions. Log with structured context, and add a failure metric when the action already has action-level telemetry or the failure is operationally important.
- When rescuing to translate an error, prefer re-raising a more specific application error class.

## Feature flags & rollout

New gated behavior should use `monolith_feature_enabled?` (see `models.instructions.md`). Cross-cutting feature-flag and PR-description rules live in `engineering-conventions.instructions.md` and `code-review-style.instructions.md`.