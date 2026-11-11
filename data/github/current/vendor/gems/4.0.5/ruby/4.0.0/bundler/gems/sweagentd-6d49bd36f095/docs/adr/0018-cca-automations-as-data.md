# Repo-Scoped, User-Owned CCA Automations

**Status:** proposed

**Deciders:** @gnfisher @timrogers

**Related issue:** https://github.com/github/sweagentd/issues/10231

## Context

We want CCA to support automations that start agent sessions in response to repository events, such as failed workflow runs or newly opened issues. The direction so far has been to model these automations as repository-level custom agents by extending the custom agent spec with an `on` field that mirrors a subset of GitHub Actions trigger syntax.

That approach has not shipped broadly yet, but some of the implementation has been dark-shipped. Today, sweagentd already syncs a subset of custom agent fields into Cosmos when custom agent files change, then uses the stored representation to evaluate incoming events and find matching agents in event handlers.

This is the right time to clarify how CCA automations are created, edited, and attributed. The current custom-agent-backed design does make automations repository-owned in the sense that they are files committed to the repository. However, it ties automation management and attribution to file commits and custom agent semantics, while CCA automations are cloud-agent product behavior. The ADR needs to decide whether we want automations to remain repo-file-backed or become repo-scoped, user-owned product resources with explicit user creation, editing, and attribution metadata.

## Current status

Custom agent definitions are markdown files with YAML frontmatter. The current spec includes fields such as `description`, `tools`, `mcp-servers`, `github.permissions`, `github.toolsets`, and `on`.

For event-based execution, sweagentd already uses a database representation of custom agent fields. Custom agent file changes are synced into Cosmos, and event handlers query those records to determine whether an incoming event should trigger a CCA job.

That cached custom agent representation is already close to what automation event matching needs: a repository-scoped record with trigger configuration, launch configuration, timestamps, and validation state. The problem is that the source of truth is still a custom agent file, which makes automations look like reusable agents rather than repository-owned CCA product data.

## Requirements

1. Automations should be repo-scoped, user-owned resources with explicit creator, editor, and human attribution metadata.
1. Automations should be created, edited, disabled, and deleted through GitHub.com UI, initially from the Mission Control agent repository view.
1. Regular users should be able to create, edit, disable, or delete only automations that they own. Future repository admin support may allow admins to view and modify any automation in a repository.
1. The automation should record the creator/owner identity that is used for management ownership, runtime attribution, billing eligibility, and permissions.
1. Triggered automation execution should run as the automation creator/owner using the same CCA runtime identity and permission model as user-started CCA work, rather than the server-to-server automation execution model.
1. The persistence model should support server-side validation before automations are saved and direct querying by event handlers.
1. The automation data model should include enough information to build the agent `Job` in sweagentd: trigger configuration, prompt, tool enablement, MCP configuration, GitHub MCP toolsets, and GitHub permissions.
1. Automations should use soft delete semantics, either via a deleted state or deleted timestamp.
1. The custom agent specification should not be expanded further to carry CCA-only automation concepts.

## Alternatives considered

### 1. Continue with custom-agent-backed automations

Continue the current hybrid direction: store automation configuration in custom agent files, sync selected fields into Cosmos, and use the Cosmos records for event matching.

**Pros:**

- Reuses the custom agent file format.
- Keeps an automation-as-code workflow where automation changes can be reviewed through repository commits.
- Reuses the existing custom agent sync path from repository files into Cosmos.
- Allows an Actions-like `on` syntax in a place that may feel familiar to users.

**Cons:**

- Blurs the product boundary between reusable custom agents and CCA-only automations, forcing every automation to also be represented as an agent.
- Pushes CCA-specific semantics into a cross-product file format, requiring GitHub.com, CLI, IDEs, and future clients to either understand or deliberately ignore automation fields.
- Creates ambiguous invocation behavior: automation-backed agents need extra rules for whether they appear in agent pickers, can be manually invoked, or can be used as subagents.
- Makes repository-owned, UI-edited automations awkward because changing them requires file writes and commits instead of direct product data updates.
- Creates two representations anyway: the file-backed custom agent and the synced Cosmos record used by event handlers.

### 2. Make automations shared repository-owned, user-attributable product resources

Treat automations as shared repository-owned resources that are created and managed through product UI/API surfaces, with explicit creator, editor, lifecycle, and human attribution metadata.

**Pros:**

- Directly models a repository-wide behavior: automations belong to repositories, can be edited by any repository writer, and still record the user who created, last edited, and is currently attributable for them.
- Cleanly separates custom agents from CCA automations.
- Avoids expanding the custom agent spec for a Mission Control and cloud-agent-specific product surface.
- Allows server-side validation before automations are saved, with structured UI feedback for invalid triggers, permissions, MCP configuration, or prompts.
- Supports UI-first creation and management without synthetic files, commits, branches, merge conflicts, file deletion, or cross-client rendering.
- Allows automation-specific lifecycle and audit fields such as `disabled`, `deleted_at`, `created_by`, `last_edited_by`, and `attributable_user_id`.

**Cons:**

- Loses the git-native workflow for reviewing automation changes.
- Requires new UI and API surfaces for create, edit, disable, and delete operations.
- Requires clear audit logging because changes happen through product data rather than repository commits.
- Requires a separate future design if we want automation-as-code support.
- Repository writers can modify automations created by other repository writers, which requires stronger UI and audit cues.

### 3. Make automations repo-scoped and user-owned

Store automations as data, keep the repository as the execution and event-matching context, but treat the creator as the automation owner for management visibility and edit permissions.

**Pros:**

- Makes it easy to identify an accountable human for each automation.
- Aligns with personal automation mental models and supports a user dashboard of automations across repositories.
- Keeps management visibility private by default: regular users see and modify only their own automations.
- Lets automation runs use the creator's normal CCA identity, permissions, and billing eligibility instead of requiring server-to-server token behavior or separate organization billing prerequisites.
- Still allows repository-scoped runtime matching, so a single repository event can trigger automations owned by multiple users.
- Leaves room for future repository admin override behavior without making every repository writer a collaborator on every automation.

**Cons:**

- Requires explicit repository admin behavior for cases where an automation affects a repository but the owner is unavailable.
- Requires a user-partitioned lookup path for cross-repository "my automations" views in addition to repository-scoped runtime lookup.
- The UI must distinguish private management visibility from repository-wide runtime effects.

## Decision

We will make CCA automations repo-scoped, user-owned, and user-attributable product data.

The source of truth for an automation will be a repo-scoped, user-owned resource created and managed through GitHub.com UI/API surfaces, starting with the Mission Control agent repository view and the `github.com/copilot/agents` user dashboard. Automations will not be represented as custom agent files.

Any user with repository write permission and an active Copilot license or seat can create automations for that repository. Regular users can list, view, edit, disable, and delete only automations that they own. The creator is the automation owner and the identity used when triggered automation runs are launched. The last editor is recorded for audit. Future repository admin support may allow admins to list, view, edit, disable, or delete any automation in the repository.

Execution uses the automation creator's CCA runtime identity. Triggered automation runs should behave like user-started CCA work owned by that creator: they use the creator's permissions and Copilot eligibility, are billed according to the same user-owned CCA rules, and do not require the separate server-to-server automation token or organization billing assumptions from the previous shared repository-owned design.

Custom agents may still be used by CCA, and future automation records may reference a custom agent if that becomes useful. However, an automation does not need to be a custom agent, and the custom agent specification should not be expanded solely to support automation behavior.

Because automations are repo-scoped UI-managed resources, they should be persisted as first-class data that sweagentd can validate and query directly. Storage is an implementation consequence of the ownership model, not the primary product decision.

## Authorization and execution model

Creating an automation requires repository write permission and an active Copilot license or seat. Editing, disabling, or deleting an automation requires repository write permission, active Copilot eligibility, and automation ownership. No stronger repository permission is required for owner-managed operations.

All normal repository access requirements still apply. For example, if the organization requires SSO authorization, verified sessions, or other access controls before a user can modify repository settings or contents, the user must satisfy those requirements before they can modify automations.

Authorization is based on current repository permissions and automation ownership. A regular repository writer cannot edit or delete an automation created by another repository writer. Future repository admin support may add an override for cross-owner management.

Create sets the automation owner to the acting user. Edit, enable, and disable operations are limited to the owning user for regular callers and do not transfer ownership. Future repository admin edits need an explicit product decision about whether they transfer ownership, merely update audit metadata, or allow an admin to repair an automation while preserving the original owner.

Execution uses the creator-owned CCA runtime model:

1. Enabled automations are evaluated by sweagentd in response to supported events.
1. If matched, sweagentd creates a CCA job using the automation's launch configuration and creator/owner identity.
1. The run uses the creator's CCA runtime identity, permissions, and Copilot eligibility instead of server-to-server tokens.
1. Requested GitHub permissions are still subject to the same limits that apply to user-started CCA work.
1. The creator/owner is the human identity for responsibility, billing eligibility, and any branch-protection collaborator behavior on pull requests created by the automation.

## Implications

### Benefits

- The ownership model is clear: automations run in a repository context but are owned and managed by individual users.
- Regular users get private management visibility, while runtime event matching can still evaluate all enabled automations for a repository.
- Triggered automation runs can reuse the creator's CCA runtime identity, permissions, and billing model instead of introducing separate server-to-server execution and organization billing requirements.
- The custom agent spec remains focused on defining reusable agents.
- Automations get a purpose-built lifecycle, validation flow, and audit trail.
- UI-created automations do not need synthetic files or commits.
- Product surfaces can clearly distinguish agents users can invoke from automations that respond to events.
- The `github.com/copilot/agents` dashboard can list a user's automations across repositories.

### Trade-offs

- Automation changes are no longer naturally reviewed through pull requests.
- Auditability must be provided by the UI and API because repository commits no longer provide the audit trail.
- We may need to store previous versions of automation definitions to satisfy audit or investigation requirements, but the exact version-history model is out of scope for this ADR.
- Future repository admin override behavior needs a separate product and authorization decision.
- User-owned management requires additional lookup paths beyond repository-scoped event matching.

## Additional details

### Proposed data shape (WIP)

The record should be shaped around repository-scoped event matching, user ownership, audit, and CCA launch configuration.

Because these automations are repo-scoped but user-owned, the storage model needs efficient repository lookup for runtime matching, user lookup for dashboards, and direct ID lookup for task-style API routes. The canonical repository-scoped record should be partitioned by repository owner and repository, with additional user-partitioned and automation-ID lookup paths owned by Mission Control.

```jsonc
{
  "id": "uuid",

  "owner_id": 98765,
  "repo_id": 123456,
  "user_id": 456,

  "disabled": null,

  "created_at": "2026-05-01T12:00:00Z",
  "updated_at": "2026-05-03T14:30:00Z",
  "deleted_at": null,

  "created_by_user_id": 123,
  "last_edited_by_user_id": 456,
  "attributable_user_id": 456,
  "deleted_by_user_id": null,

  "name": "Issue triage",
  "description": "Triages newly opened issues.",
  "triggers": { "issues": { "types": ["opened"], "query": "label:auto-triage" } },
  "prompt": "When a new issue is opened, inspect it and suggest labels, priority, and next steps.",
  "tools": ["read", "edit", "bash", "github/*"],
  "permissions": { "contents": "read", "issues": "write" },
  "github_mcp_toolsets": ["context", "issues"],
  "mcp_servers": [
    { "name": "example-server", "type": "http", "url": "https://example.com/mcp", "tools": ["*"] }
  ]
}
```

Notes:

- `repo_id` is the primary repository event matching key.
- `owner_id` is the repository owner ID. It supports owner-scoped lookup and future indexing options, but this ADR does not decide whether org-level automations will exist.
- `user_id` is the automation owner. Regular management APIs only return records where `user_id` is the authenticated user ID. Runtime event queries are repository-scoped and may return enabled automations across many `user_id` values.
- `disabled` is `null`/absent for enabled automations. Disabled automations store lifecycle metadata such as `reason`, `disabled_at`, and optional `disabled_by_user_id`; disabled automations are excluded from trigger matching without deleting configuration.
- `created_by_user_id` and `last_edited_by_user_id` are durable audit fields for configuration changes.
- `attributable_user_id` is the human identity used for responsibility, runtime ownership, billing eligibility, and co-attribution signals on future pull requests and commits created by the automation. For regular users this is the creator/owner and should not change on edits.
- `triggers` stores the normalized trigger configuration. See [Trigger schema](#trigger-schema).
- `prompt` is the automation instruction used to launch the CCA session.
- `tools`, `permissions`, `github_mcp_toolsets`, and `mcp_servers` describe the execution environment using names similar to the existing cached custom agent config.
- `github_mcp_toolsets` controls which GitHub MCP server toolsets are enabled. `tools` still controls which tools the agent may use. For example, enabling the `repos` toolset does not by itself require exposing every repo tool to the agent; `tools: ["github/*"]` would expose all enabled GitHub tools, while `tools: ["github/get_issue"]` would allow only that specific tool if its toolset is enabled.
- `deleted_at` provides soft delete semantics.

### Trigger schema

`triggers` stores the normalized trigger configuration for an automation. It follows the GitHub Actions `on:` event model where practical: trigger keys should use Actions event names, event activity should use `types`, and event-specific filters should use Actions field names when Actions already has an equivalent field.

The stored shape is normalized JSON rather than YAML. Product APIs and UI forms may expose simpler controls, but writes should validate and normalize into this shape before persistence. Unsupported events or fields should be rejected rather than stored as opaque data.

Some useful CCA automations need to narrow broad events before an agent session starts. GitHub Actions often handles those cases with job-level `if` expressions rather than `on:` fields, such as checking whether a workflow run failed or whether a pull request was merged. For CCA, those should be modeled as explicit, event-specific filter fields only when needed, and they should be mechanically translatable to equivalent Actions conditions where possible.

Initially supported or expected trigger blocks:

| Trigger key | Status | Shape | Actions-aligned meaning |
| --- | --- | --- | --- |
| `interval` | Required initial | `{ "types": ["daily" \| "weekly"] }` | CCA-managed replacement for `schedule`; not cron, to avoid thundering herd. |
| `issues` | Required initial | `{ "types": ["opened"], "query": "label:auto-triage" }` | Equivalent to `on.issues.types`; `query` is a CCA pre-run filter using a restricted GitHub issue search syntax. |
| `pull_request` | Likely follow-up | `{ "types": ["opened" \| "synchronize" \| "labeled" \| "closed"] }` | Equivalent to `on.pull_request.types`. `synchronize` is the Actions activity for pushes to a PR branch. |
| `issue_comment` | Likely follow-up | `{ "types": ["created"] }` | Equivalent to `on.issue_comment.types`; applies to comments on both issues and pull request conversations, matching Actions semantics. |
| `pull_request_review_comment` | Likely follow-up | `{ "types": ["created"] }` | Equivalent to `on.pull_request_review_comment.types`; applies to pull request diff comments. |
| `workflow_run` | Existing custom-agent behavior to revise | `{ "types": ["completed"], "workflows": ["CI"], "conclusions": ["failure"] }` | Equivalent to `on.workflow_run.types` and `on.workflow_run.workflows`; `conclusions` is a CCA pre-run filter corresponding to `github.event.workflow_run.conclusion`. |

Rules:

- Trigger config is an object keyed by Actions event name, except for CCA-specific `interval`.
- Each event key appears at most once.
- Event trigger blocks must specify explicit `types`; shorthand forms are not stored.
- `types` should use GitHub Actions activity names where an Actions event exists.
- Future trigger fields should prefer Actions field names when available.
- CCA-only filter fields should be event-specific and typed, not a general expression language.

### Plugin and agentic app implications

Moving CCA automations out of custom agent files has downstream implications for future plugin and agentic app automation stories. If triggers are no longer expressed as files in the repository, then plugins cannot rely on the custom agent file path as the only way to contribute event-driven behavior.

This ADR does not decide the future plugin product model, and plugin-provided automations are not part of the initial scope. However, the data-backed model should preserve a path for that future: sweagentd should expose a service/API registration path that creates or updates the same automation records after server-side validation. A future plugin or agentic app system could read trigger details from a plugin manifest, such as `plugin.json`, and register corresponding automation records without re-implementing trigger matching or requiring the triggers to live in custom agent files.

Open product questions remain for that future work.
