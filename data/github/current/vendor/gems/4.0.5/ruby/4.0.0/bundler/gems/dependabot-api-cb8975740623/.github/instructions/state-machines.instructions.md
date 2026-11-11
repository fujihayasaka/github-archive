---
applyTo: "app/state_machines/**/*.rb"
---

# State Machine Code Review Rules

State machines use **Statesman** (`include Statesman::Machine`). Reference: `app/state_machines/update_job_state_machine.rb`, `app/state_machines/account_state_machine.rb`.

## Required structure

- Declare every state with `state :name`, including the initial state with `state :name, initial: true`.
- Declare every transition with `transition from: ..., to: ...`. Reviewers should reject "open" state machines.
- Add a guard for transitions with preconditions:

  ```ruby
  guard_transition(to: :processed_with_errors) do |update_job|
    update_job.errors.any?
  end
  ```

  Verify the guard enforces the actual business invariant (e.g., `processed_with_errors` requires errors to exist).

## Callbacks

- **`before_transition`** is commonly used to persist metadata into columns (e.g., `update_job.update!(hashed_token: nil, ...)`) and may also enqueue follow-up jobs that should be triggered atomically with the transition. Existing examples: `update_job_state_machine.rb` enqueues `CancelActionsWorkflowRunJob` from a `before_transition`.
- **`after_transition(after_commit: true)`** is preferred for side effects that depend on the transition being durably committed — typically logging, metrics, and notifications.
- When reviewing a callback that performs side effects in `before_transition`, verify the side effect is intentional, rollback-safe (e.g., enqueuing a job that will no-op if the transition is rolled back), and not dependent on the new state being visible to readers.
- Avoid heavy synchronous business logic in callbacks; delegate to actions or jobs.

## Reviewer checklist

- New transitions have at least one test for both happy-path and guard-rejection cases.
- Logging/metrics in `after_transition` use the same key conventions as actions (see `actions.instructions.md`).
- If a callback uses `Dependabot::Logger.public_send(level, ...)` to dispatch dynamically, verify `level` is bounded to a known set (`:info`, `:warn`, `:error`).
- New states are exhaustively handled by any `case`/dispatch tables that switch on state.
