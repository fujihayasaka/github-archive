# ADR: Custom Agent Triggers

Date: 2026-01-20

Status: proposed

Deciders: @arthurnn @chuxel @josebalius @kelseyrae @friggeri @colbylwilliams

Related issue: `TODO`

## Context

To support a wider variety of use cases for agent sessions, we want to enable triggering agent sessions based on events, similar to how GitHub Actions workflows can be triggered by various events (e.g., issue opened, pull request opened, workflow run failed, schedule).

Custom agents today are invoked on-demand via direct user interaction (e.g., assigning Copilot to an issue). This limits their utility for automated workflows like:

- Automatically fixing failed CI runs (highest priority - `workflow_run`)
- Running scheduled maintenance or analysis tasks (`interval`)
- Triaging newly opened issues (`issues`)
- Reviewing or validating newly opened pull requests (`pull_request`)

### Current Status

The `CustomAgentTriggers` struct currently only supports the `Issues` trigger type. Event handling infrastructure exists for multiple event types (see `internal/events/handler.go`), but only `OnIssueCreated` integrates with custom agent triggers.

**Implemented:**

- `issues.opened` trigger with full job building and execution flow

**Event handlers exist but not integrated with custom agent triggers:**

- `OnWorkflowRunCompleted` - handles workflow run completions (used for job finalization)
- `OnPullRequestStateChanged` - handles PR close/merge events (used for job cancellation)
- `OnPullRequestCommentCreated` - handles PR comment events
- `OnPullRequestReviewSubmit` - handles PR review events

### Requirements

1. **Minimal gh/gh changes**: sweagentd should own trigger evaluation logic; gh/gh only notifies of config changes (see [ADR 0006](0006-custom-agent-configs.md)).
2. **Actor resolution**: Every triggered session needs a valid actor for CAPI (Copilot API) quota and permissions.
3. **Actions-like syntax**: Trigger configuration should feel familiar to users of GitHub Actions.
4. **Scalability**: Must handle high event volume without overwhelming the system (especially for interval triggers).
5. **Feature flag gating**: All triggers should be gated behind `copilot_swe_agent_custom_agent_triggers` feature flag.

## Alternatives Considered

### 1. [Agentic Workflows](https://github.com/githubnext/gh-aw)

A separate system for defining agent-based workflows with its own syntax and execution model.

**Pros:**

- Purpose-built for agentic use cases
- Could support more complex multi-agent orchestration

**Cons:**

- Requires users to learn a new system
- Duplication of effort with existing Actions infrastructure
- Separate deployment and maintenance burden

### 2. Make Agents a First-Class Citizen in GitHub Actions

Integrate agent invocation directly into GitHub Actions workflows (e.g., `uses: github/copilot-agent@v1`).

**Pros:**

- Leverages existing Actions infrastructure and user familiarity
- Access to full Actions feature set (matrix builds, caching, etc.)

**Cons:**

- Significant changes to Actions required
- Agent sessions are long-running and don't fit the Actions job model well
- Billing and quota models differ between Actions and Copilot

### 3. Simple Event-Based Triggers (Chosen)

Define a subset of Actions-like triggers specifically for agent sessions, with sweagentd owning the evaluation and execution.

**Pros:**

- Familiar syntax for Actions users
- sweagentd controls the entire lifecycle
- Can start simple and expand based on user feedback
- No Actions changes required

**Cons:**

- Some trigger features won't be available (e.g., complex path filters, concurrency groups)
- Users may expect full Actions parity

## Decision

Implement a subset of GitHub Actions-style event triggers for custom agents, with trigger definitions in the agent's YAML frontmatter. sweagentd owns trigger evaluation and job creation.

**Key design choices:**

1. **Actions-like syntax with simplifications**: Use `on:` key with event types, but start with simpler filter options.
2. **`interval` instead of `schedule`**: Use coarse-grained intervals (daily, weekly) instead of cron to avoid thundering herd problems.
3. **Trigger-specific actor resolution**: Each trigger type defines its own actor resolution strategy.
4. **Expand `CustomAgentTriggers` struct**: Add `Workflow`, `Interval`, and `PullRequest` fields alongside existing `Issues`.
5. **Prioritized rollout**: Implement triggers in order of user value: `workflow_run` → `interval` → `issues` → `pull_request`.

## Implications

1. **Incremental rollout**: We do not want to re-implement all of GitHub Actions' event triggers, so we will start with a small set of commonly used triggers that make sense specifically for agent sessions to validate the concept and gather user feedback.
2. **Scalability and cost**: Running agent sessions on various triggers (e.g., frequent interval runs) has compute and quota implications that need monitoring.
3. **Actor/permissions complexity**: User permissions and security considerations for triggers that involve user actions (e.g., who can trigger an agent session on their behalf). The actor model varies by trigger type.
4. **Config persistence dependency**: Full trigger support requires the config persistence work outlined in [ADR 0006](0006-custom-agent-configs.md) for efficient trigger evaluation.

## Supported Triggers

> [!IMPORTANT]
> The triggers below are listed in order of implementation priority.

### 1. `workflow_run`

```yaml
on:
  workflow_run:
    types:
      - failed
    workflows:
      - ci.yml
      - tests.yml
```

The `workflow_run` trigger fires when a GitHub Actions workflow run completes. This is the highest priority trigger as it enables the compelling "auto-fix failed CI" use case. Our implementation simplifies [GitHub Actions' `workflow_run`](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run) by focusing on `types` like `failed` rather than the separate `conclusion` and `status` concepts.

> [!NOTE]
> This event will only trigger if the agent configuration file exists on the default branch.

#### Types

| Type | Description | Status |
| ---- | ----------- | ------ |
| `failed` | Trigger when a workflow run fails | ✅ Implemented ([#10239](https://github.com/github/sweagentd/pull/10239)) |
| `completed` | Trigger on any workflow completion | 🔮 Future |
| `success` | Trigger when a workflow succeeds | 🔮 Future |

#### Filters & Constraints

| Filter | Description | Required | Status |
| ------ | ----------- | -------- | ------ |
| `workflows` | List of workflow file names to trigger on (e.g., `ci.yml`) | No | ✅ Implemented ([#10239](https://github.com/github/sweagentd/pull/10239)) |
| `branches` | Branch names or patterns to filter runs | No | 🔮 Future |

**Branch matching:** We may need to support [complex branch matching](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_runbranchesbranches-ignore) syntax for consistency with GitHub Actions. Initially, we'll support simple branch name lists.

#### Actor

Workflow run actor resolution is complex because workflow runs don't always have a clear human actor:

| Workflow Trigger | Actor Resolution Strategy |
| --------------- | ------------------------- |
| `push` by user | User who pushed the commit |
| `pull_request` | User who opened/updated the PR |
| `schedule` | **Requires fallback** - see `interval` trigger |
| `workflow_dispatch` | User who triggered the dispatch |
| `workflow_run` (chained) | Original triggering user (if available) |

**Fallback actor for scheduled/automated runs:** When no human actor is available, the session may need to use a pre-configured service account or bot. This requires additional configuration (see `interval` trigger for the actor consent model).

---

### 2. `interval`

```yaml
on:
  interval:
    types:
      - daily
```

We use `interval` instead of `schedule` (cron) like Actions for periodic trigger invocation, allowing coarse-grained timing (e.g., daily, weekly). This trigger enables use cases like scheduled code maintenance, dependency updates, and periodic analysis tasks.

#### Benefits of `interval` over `schedule` (cron)

1. **Resource optimization**: Utilize cloud resources (GPUs) outside of normal high-use business hours
2. **Avoid thundering herd**: Actions experiences issues where a majority of cron jobs run at the same time (12:00 UTC), overloading the system. By using intervals, sweagentd controls execution timing.
3. **Simplicity**: No cron syntax to learn or debug

#### Types

| Type | Description | Guaranteed Execution | Status |
| ---- | ----------- | ------------------- | ------ |
| `daily` | Run once per calendar day | At least once every 24 hours, during off-peak hours | 🚧 Planned |
| `weekly` | Run once per week | At least once every 7 days, during off-peak hours | 🚧 Planned |

**Timing semantics:**

- `daily`: Guaranteed to run at least once every 24 hours, but the exact time is controlled by sweagentd to optimize resource usage
- `weekly`: Guaranteed to run at least once every 7 days
- Actual execution time may vary to distribute load across the system

#### Filters & Constraints

None currently planned. Future options might include:

| Filter | Description | Status |
| ------ | ----------- | ------ |
| `timezone` | Timezone for "daily" definition | 🔮 Future |
| `day-of-week` | Specific day for weekly runs | 🔮 Future |

#### Actor

Interval-triggered sessions require special actor handling since there is no user action to derive an actor from. This actor model also applies to `workflow_run` triggers when the original workflow was triggered by a schedule or another automated process.

**Options under consideration:**

1. **Pre-configured service account**: A bot or service account defined at the org/enterprise level with necessary permissions and Copilot license.

2. **Actor specified in trigger config**:

   ```yaml
   on:
     interval:
       types: [daily]
       actor: @service-bot
   ```

3. **Dedicated Copilot service identity**: A Copilot-owned identity for automated operations.

**Consent problem:** If we allow specifying an actor handle in the trigger definition, we need a consent mechanism to prevent quota abuse:

> Example: User A adds `@userB` as the actor for their interval trigger, consuming User B's Copilot quota without consent.

**Proposed solution:** Require explicit opt-in from the specified actor, either through:

- A separate configuration file in the user's profile
- A UI confirmation flow
- Restricting to org-configured service accounts only

---

### 3. `issues`

```yaml
on:
  issues:
    types:
      - opened
```

The `issues` trigger fires when issue events occur in the repository. This trigger enables use cases like automated issue triage, initial investigation, or immediate response to bug reports.

> [!NOTE]
> The trigger uses `issues` (plural) to match GitHub Actions syntax.

#### Types

| Type | Description | Status |
| ---- | ----------- | ------ |
| `opened` | Trigger when a new issue is created | ✅ Implemented |
| `labeled` | Trigger when a label is added to an issue | 🔮 Future |
| `assigned` | Trigger when the issue is assigned | 🔮 Future |

#### Filters & Constraints

| Filter | Description | Status |
| ------ | ----------- | ------ |
| `labels` | Only trigger for issues with specific labels | 🔮 Future |

#### Actor

The actor for issue-triggered sessions is the user who opened the issue.

**Considerations:**

- The actor must have a valid Copilot license for CAPI quota
- Depending on repository settings, it may be necessary to restrict triggers to collaborators only
- A configuration option may be needed to specify actor restrictions:

```yaml
on:
  issues:
    types: [opened]
    # Future: restrict to collaborators only
    # collaborators-only: true
```

---

### 4. `pull_request`

```yaml
on:
  pull_request:
    types:
      - opened
```

The `pull_request` trigger fires when pull request events occur in the repository. This enables use cases like automated code review, documentation validation, or security scanning on new PRs.

#### Types

| Type | Description | Status |
| ---- | ----------- | ------ |
| `opened` | Trigger when a new PR is created | 🚧 Planned |
| `synchronize` | Trigger when new commits are pushed to the PR | 🔮 Future |
| `reopened` | Trigger when a closed PR is reopened | 🔮 Future |
| `labeled` | Trigger when a label is added | 🔮 Future |

#### Filters & Constraints

| Filter | Description | Status |
| ------ | ----------- | ------ |
| `branches` | Target branch names to filter PRs | 🚧 Planned |
| `paths` | File path patterns to filter by changed files | 🔮 Future |

**Branch matching:** Initially, we'll support simple branch name lists (e.g., `[main, develop]`). If we need to support [complex branch matching](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#onworkflow_runbranchesbranches-ignore) for `workflow_run`, we should support it here as well for consistency.

```yaml
on:
  pull_request:
    types: [opened]
    branches:
      - main
      - 'release/**'  # Future: glob patterns
```

#### Actor

The actor for pull request triggered sessions is the user who opened (or updated) the PR.

**Considerations (same as `issues` trigger):**

- The actor must have a valid Copilot license for CAPI quota
- May need to restrict to collaborators based on repository settings
- Fork PRs may need special handling (external contributors)

---

## Implementation Status

Components are listed in implementation priority order.

| Priority | Component | Status | Notes |
| -------- | --------- | ------ | ----- |
| 1 | `CustomAgentTriggers.WorkflowRun` | ✅ Done | [PR #10239](https://github.com/github/sweagentd/pull/10239) |
| 1 | `workflow_run.failed` handler | ✅ Done | [PR #10239](https://github.com/github/sweagentd/pull/10239) |
| 2 | `CustomAgentTriggers.Interval` | ❌ Not started | Struct field needed |
| 2 | Schedule Processor | ❌ Not started | Depends on [ADR 0006](0006-custom-agent-configs.md) config persistence |
| 3 | `CustomAgentTriggers.Issues` | ✅ Done | `internal/sweagentd/customagent.go` |
| 3 | `issues.opened` handler | ✅ Done | `internal/events/on_issue_created.go`, [PR #10234](https://github.com/github/sweagentd/pull/10234) |
| 4 | `CustomAgentTriggers.PullRequest` | ❌ Not started | Struct field needed |
| 4 | `pull_request.opened` handler | ❌ Not started | PR state events now handled by sessions service |

---

## Related Documents

- [ADR 0005: Custom Agents Specification](0005-custom-agents.md) - Agent config file format and API
- [ADR 0006: Custom Agent Definition Detection](0006-custom-agent-configs.md) - Config sync and persistence architecture
