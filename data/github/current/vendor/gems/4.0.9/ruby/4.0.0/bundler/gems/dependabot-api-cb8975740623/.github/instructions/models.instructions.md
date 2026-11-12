---
applyTo: "app/models/**/*.rb"
---

# Model Code Review Rules

ActiveRecord models with MySQL (Trilogy). Reference: `app/models/account.rb`, `app/models/repo.rb`, `app/models/update_job.rb`.

## Feature flags (CRITICAL — see `lib/rubocop/cop/dependabot/no_local_feature_flags.rb`)

This codebase uses **monolith feature flags**. Local Flipper-based flags are **deprecated** and the `Dependabot/NoLocalFeatureFlags` RuboCop cop catches them.

### Use these:

```ruby
# Per-model helpers
repo.monolith_feature_enabled?(:dependabot_my_feature)
repo.monolith_feature_enabled?(:dependabot_my_feature, use_cache: false)

account.monolith_feature_enabled?(:dependabot_my_feature)

# Application-level (when no actor is implicit)
Dependabot::Application.monolith_feature_enabled?(
  feature: :dependabot_my_feature,
  actor: repo,                # or account, or nil for global
  use_cache: true,            # optional
  fail_state: false,          # optional — value to return on lookup failure
)
```

The `monolith_actor` method on `Account` and `Repo` returns the proper `FeatureFlags::Actor::*` wrapper if you need to pass an actor explicitly.

### Don't flag — but don't expand:

Live code still uses the deprecated methods in some legacy paths with `# rubocop:disable Dependabot/NoLocalFeatureFlags` annotations. Those are accepted; don't flag them. **Do** flag:

- A new call without the rubocop disable comment.
- A widened suppression scope covering new code added in the same PR.
- A new suppression added without justification.

### Reject these (when introduced as new code):

- `repo.config_feature_enabled?(:foo)` / `update_job.config_feature_enabled?(:foo)`
- `repo.org_level_flag_enabled?(:foo)` / `repo.repo_level_flag_enabled?(:foo)`
- `repo.enable_feature(:foo)` / `repo.disable_feature(:foo)`
- `Dependabot.flipper[:foo]`

If existing code includes a `# rubocop:disable Dependabot/NoLocalFeatureFlags` line, do not silently extend it to new code. Each suppression should be narrowly scoped and justified.

### Naming

Monolith flags must be prefixed with `dependabot_` (e.g., `:dependabot_my_feature`).

## Validations & schema alignment

When changing a column or validation, also update the JSON schema, factory defaults, and example payloads. The cross-cutting rule lives in `engineering-conventions.instructions.md`. The model-specific concern: if `validates :foo, presence: true` is added, the corresponding Twirp request type and JSON schema should also mark `foo` as required, and the handler should return `Twirp::Error.invalid_argument` when it's missing.

## Scopes

- Keep scopes simple, composable, and side-effect-free.
- Don't define a scope that triggers callbacks or external calls.

## Method signature changes

When changing a model method's signature, update **every** call site in the same PR. Specs that stub the method will not catch the mismatch. (See `engineering-conventions.instructions.md` for the cross-cutting rule.)

## Polymorphic associations & deletion safety (CRITICAL)

When writing or modifying a method that deletes records:

- For polymorphic associations (e.g., ActiveStorage attachments where multiple parent types share `record_id`), **always scope the delete by `record_type` as well**.
- Cascading deletes (`dependent: :destroy`, `dependent: :delete_all`, custom `delete_all_with_dependents` helpers) on polymorphic models can wipe out unrelated rows — review every such call carefully.
- Cleanup helpers must be idempotent and safe under retries (delete-many should not raise if the records are already gone).

## Telemetry & logging

- Many model methods are telemetry-aware. When refactoring a method, preserve its `MetricsClient.increment` and `Dependabot::Logger` calls unless the metric is genuinely no longer meaningful.
- New conditional behavior should have its own metric tag so we can observe its frequency in production.

## GitHub API access

When a model method calls the GitHub API:

- Prefer `GitHubHelpers::ClientWithRetries.new(account: ..., repo_ids: ..., permissions: ...)` over `Octokit::Client.new` directly (see `app/models/pull_request.rb`, `app/models/pull_request_commits.rb`, `app/models/autofix_suggestion_job.rb`).
- For paginated list endpoints, use `GitHubHelpers.fetch_all_pages` (see `app/models/activity/paused_pull_request_helper.rb`).

## Reviewer checklist

- New gated behavior uses `monolith_feature_enabled?` with a `dependabot_`-prefixed name.
- Method signature changes are reflected at every call site.
- Deletion logic is scoped against polymorphic association hazards.
- Schema/validation/factory/example are updated together.
