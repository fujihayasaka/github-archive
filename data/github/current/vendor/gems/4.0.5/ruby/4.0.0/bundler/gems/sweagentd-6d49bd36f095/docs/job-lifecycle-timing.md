# Job Lifecycle Timing — Metrics Reference

> This document describes all timing metrics and timestamps captured throughout
> the lifecycle of a sweagentd job. Use it as a reference when debugging latency,
> building dashboards, or adding new instrumentation.

---

## 1. Lifecycle Overview

A job passes through a series of stages from request to completion. Each stage
transition is marked by a timestamp on the `Job` struct and, in most cases, an
associated duration metric.

```
┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│                                              Job Lifecycle                                                       │
│                                                                                                                  │
│  ┌──────────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌────────────┐   │
│  │   Request    │──►│  Build   │──►│  Queued  │──►│ Launched │──►│ Started  │──►│ Running  │──►│ Completed  │   │
│  │  Received    │   │(Prepare) │   │          │   │          │   │          │   │          │   │            │   │
│  └──────┬───────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   └────┬─────┘   └─────┬──────┘   │
│         │                │              │              │              │              │               │           │
│  RequestStartedAt   PreparedAt     QueuedAt       LaunchedAt     StartedAt      RunningAt      CompletedAt      │
│  CreatedAt                                                                                                       │
│                                                                                                                  │
│  Segment Metrics (adjacent stage durations):                                                                     │
│                          ├─ prepared_to_queued ─┤                                                                │
│                                       ├── queue_wait_duration_ms ──┤                                             │
│                                                         ├── launched_to_started ──┤                              │
│                                                                       ├─ started_to_running ─┤                   │
│                                                                       ├──── execution_duration_ms ───────────┤   │
│                                                                                                                  │
│  Spanning Metrics (multi-stage durations):                                                                       │
│         ├───────────────────── request_to_launched ───────────────┤                                           │
│         ├───────────────────── request_to_started_ms ───────────────┼──────────┤                                │
│         ├───────────────────── request_to_running ──────────────────┼──────────┼──────────┤                     │
│    ├──────────────────────────── total_duration_ms (from CreatedAt) ─────────────────────────────────────┤       │
│                                                                                                                  │
│  Counter Metrics:                                                                                                │
│    • jobs.state_transition — emitted on every status change (tags: from, to)                                     │
│    • jobs.finalize — emitted at terminal state (tags: status)                                                    │
│    • jobs.completion — SLO tracking (tags: status, slo_result, failure_type, error_service, error_code)          │
│    • dynamic_workflow_creation — on workflow dispatch to Actions (tags: success)                                  │
└───────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### What each stage means

- **Request Received** — The very first moment the system becomes aware of a
  job. For REST/Twirp this is the HTTP request arriving at sweagentd. For Hydro
  events this is the moment the triggering action happened on GitHub (issue
  created, PR comment posted, review submitted, etc.) as recorded in the Hydro
  envelope timestamp. This is the "clock starts" moment for end-to-end latency.

- **Build (Prepare)** — The job preparation phase where `JobBuilder.Build()`
  assembles everything the agent needs before the job can be queued for
  execution. This is typically the most variable phase under sweagentd's control
  and involves multiple external API calls: looking up or creating assignments,
  determining which model to use, creating Git branches, opening pull requests,
  generating AI names for sessions/branches, creating CAPI sessions, and
  checking branch protection rules. See [Section 6](#6-what-the-build-phase-includes)
  for the full list.

- **Queued** — The job is fully prepared and has been placed into the aqueduct
  execution queue. It is waiting for an executor worker to pick it up. The job
  is ready to run but may be delayed by concurrency limits, rate limiting, or
  simply worker availability. The job status transitions to `queued` at this
  point.

- **Launched** — An executor worker has picked up the job from the queue,
  validated permissions and quota, constructed the workflow YAML, and
  successfully called `CreateDynamicWorkflowRun` on the GitHub Actions API.
  The dynamic workflow is now dispatched and the job status transitions to
  `running`. Note: the time between Queued and Launched includes both
  actual queue wait time AND executor processing (quota checks, launch option
  construction, workflow generation). See [Section 7](#7-what-the-executor-phase-includes)
  for what the executor does.

- **Started** — The GitHub Actions runner has picked up the dispatched workflow,
  provisioned a VM, and the agent process has booted. This is reported back to
  sweagentd via an agent callback. The time between Launched and Started is
  entirely within GitHub Actions infrastructure (runner provisioning, job
  scheduling) and is outside sweagentd's control.

- **Running** — The agent has completed its initialization (cloning the repo,
  installing dependencies, setting up the firewall, etc.) and has made its
  first LLM tool call or response. This indicates the agent's reasoning loop
  is actively working on the problem. The distinction between Started and
  Running captures the agent's setup overhead before productive work begins.

- **Completed** — The GitHub Actions workflow run has finished. This is detected
  via a `workflow_run_completed` Hydro event. The job enters a terminal status:
  `completed` (success), `failed`, `cancelled`, or `timed_out`. All final
  duration metrics are emitted at this point.

---

## 2. Timestamps

All timestamps are stored as `int64` (Unix seconds) on the `Job` struct
(`internal/jobs/job.go`).

| Field | When Set | Set By | Description |
|---|---|---|---|
| `RequestStartedAt` | HTTP request / Twirp hook / Hydro event creation | REST middleware (`jobapi/handler.go:776`), Twirp hook (`twirpserver.go:89`), Hydro event `Timestamp` field | The moment the external request was received by the service (REST/Twirp) or when the triggering event was originally created/published in the Hydro pipeline (Hydro). For Hydro events this is the envelope timestamp — e.g., when the issue was created or the PR comment was posted — giving true end-to-end latency from user action. |
| `CreatedAt` | Job insert into DB | Job store | When the job record was first persisted. For async REST/Twirp flows, this happens early (before the full Build), so it may precede `PreparedAt` significantly. |
| `PreparedAt` | End of full `Build()` | `builder.go` | When `JobBuilder.Build()` finishes — all preparation steps (branch, PR, session, AI names, experiments) are done and the job is ready to be queued. Only set on full builds; partial builds (`WithoutCreatingFeatures` in async REST) skip this to avoid inflating timing calculations with API queue wait time. |
| `QueuedAt` | `QueueJobForExecution` | `queue.go:174` | When the job was placed in the aqueduct execution queue, ready for an executor worker to pick up. |
| `WasDelayed` | `ProcessJob` (executor) | `jobexecutor.go` | Boolean set to `true` if the job was ever requeued due to rate or concurrency limits (`AgentJob.RequeueCount > 0`). Persisted to DB for use in downstream metrics. |
| `LaunchedAt` | After `CreateDynamicWorkflowRun` returns | `jobexecutor.go:504` → `UpdateJobForLaunched` | When the dynamic workflow was successfully submitted to GitHub Actions. The executor has finished all its work (quota, permissions, workflow generation) and the job is now in GitHub's hands. |
| `StartedAt` | Agent callback | Agent runtime callback handler | When the Actions runner picks up the job and the agent process starts. Everything between `LaunchedAt` and `StartedAt` is GitHub Actions infrastructure time (runner provisioning, scheduling). |
| `RunningAt` | Agent callback | Agent runtime callback handler | When the agent makes its first tool call / LLM response. This marks the transition from agent setup (repo clone, dependency install, firewall setup) to productive work. |
| `CompletedAt` | Workflow completion event | `on_workflow_run_completed.go` | When the GitHub Actions workflow run finishes (success, failure, cancellation, timeout). |

---

## 3. Entry Point Flows

Jobs arrive through three different entry points. The flow differs in how
`Build()` is called and where `RequestStartedAt` is captured.

### 3a. REST API (sync — `HandleNewJob`)

```
middleware sets RequestStartedAt
  → createJob() calls builder.Build()     ← PreparedAt set here
  → QueueJobForExecution()                ← QueuedAt set here
  → Return 201 to client
```

### 3b. REST API (async — `HandleNewJobAsync`)

```
middleware sets RequestStartedAt
  → createJob() calls builder.Build()     ← partial build (WithoutCreatingFeatures)
                                             PreparedAt NOT set (partial build skipped)
  → QueueJobForProcessing()               ← job goes to API queue
  → Return 201 to client
  ...later, aqueduct picks up APIJob...
  → Process() calls builder.Build()       ← PreparedAt set here (full build)
  → QueueJobForExecution()                ← QueuedAt set here
```

> **Note:** `PreparedAt` is only set on full builds. Partial builds
> (`WithoutCreatingFeatures`) skip setting it so that timing calculations
> reflect only the real Build phase, not the API queue wait between the two
> Build calls.

### 3c. Twirp RPC (`CreateJobForAssignment`)

```
ServerHooks.RequestReceived sets RequestStartedAt
  → CreateJobForAssignment()
  → builder.Build()                       ← PreparedAt set here
  → QueueJobForProcessing()               ← job goes to API queue
  ...later, aqueduct picks up APIJob...
  → Process() calls builder.Build()       ← PreparedAt updated here
  → QueueJobForExecution()                ← QueuedAt set here
```

### 3d. Hydro Events (issues, PR comments, reviews, code scanning)

```
Event originally created (issue, comment, review, etc.)
  → Hydro publishes event with envelope timestamp
  → sweagentd Hydro consumer receives event
  → event handler calls builder.Build()   ← PreparedAt set here
    .WithRequestStartedAt(event.Timestamp) ← envelope timestamp (event creation time)
  → QueueJobForExecution()                ← QueuedAt set here
  NOTE: RequestStartedAt uses the Hydro envelope timestamp — when the event was
        originally produced — NOT when sweagentd received the message. This captures
        Hydro pipeline latency in the end-to-end timing.
```

### 3e. Execution (all paths converge)

```
Aqueduct picks up AgentJob
  → jobexecutor.ProcessJob()
    → checkQuota()
    → launchOptsForJob()
    → launchAgent()
      → launcher.LaunchAgent()
        → CreateDynamicWorkflowRun()      ← workflow submitted
      → UpdateJobForLaunched()            ← LaunchedAt set here
  ...Actions runner starts...
  → Agent callback: StartedAt
  → Agent callback: RunningAt
  ...agent completes...
  → on_workflow_run_completed: CompletedAt
```

---

## 4. Duration Metrics

### 4a. Existing Metrics

| Metric | Formula | Emitted In | Tags | Description |
|---|---|---|---|---|
| `jobs.request_to_started_ms` | StartedAt − RequestStartedAt | `jobservice.go` (`UpdateJob` when StartedAt patch is applied) | standard† | Full end-to-end latency from the original request/event to the agent process starting on an Actions runner. This is the number users "feel" — it includes everything: preparation, queuing, executor processing, workflow dispatch, and runner provisioning. |
| `jobs.request_to_running` | RunningAt − RequestStartedAt | `jobservice.go` (when RunningAt patch is applied) | standard | Full end-to-end latency from the original request/event to the agent making its first productive action (tool call/LLM response). Compared to `request_to_started_ms`, this additionally includes the agent's initialization overhead (repo clone, dependency install, etc.). |
| `jobs.launched_to_started` | StartedAt − LaunchedAt | `jobservice.go` (when StartedAt patch is applied) | standard | Time for the GitHub Actions infrastructure to pick up the dispatched workflow and start the agent process. This is entirely outside sweagentd's control — it reflects Actions runner availability and scheduling. |
| `jobs.started_to_running` | RunningAt − StartedAt | `jobservice.go` (when RunningAt patch is applied) | standard | Agent initialization overhead: time from when the agent process starts to when it makes its first productive action. This includes repo cloning, dependency installation, firewall setup, and the first LLM call. |
| `jobs.queue_wait_duration_ms` | LaunchedAt − QueuedAt | `jobservice.go` `UpdateJobForLaunched` | standard | Time from when the job enters the execution queue to when the workflow is successfully dispatched to Actions. **Includes both actual queue wait time AND executor processing** (quota check, permissions, launch options, workflow generation, API call). |
| `jobs.request_to_launched` | LaunchedAt − RequestStartedAt | `jobservice.go` `UpdateJobForLaunched` | standard | Full end-to-end latency from the original request/event to the workflow being dispatched to GitHub Actions. This covers everything under sweagentd's control: preparation, queuing, and executor processing. |
| `jobs.total_duration_ms` | CompletedAt − CreatedAt | `jobservice.go` `FinalizeJob` | standard + `terminal_state` | Full job lifecycle from DB record creation to completion. Note: for async flows, `CreatedAt` is set early (before full Build), so this may be longer than `request_to_started_ms` + `execution_duration_ms`. |
| `jobs.execution_duration_ms` | CompletedAt − StartedAt | `jobservice.go` `FinalizeJob` | standard + `terminal_state` | How long the agent actually ran on the Actions runner, from process start to workflow completion. This is the "compute cost" metric. |
| `dynamic_workflow_creation` | Counter (success/failure) | `actions.go` | `success` | Count of `CreateDynamicWorkflowRun` API calls. Use to track success rates and call volume. |
| `dynamic_workflow_completed` | WorkflowRun.UsageMs | `on_workflow_run_completed.go` | session tags + `workflow_run_conclusion`, `session_error_code`, `agent_id`, `agent_slug`, `processing_request_conclusion` | GitHub-reported billable workflow run usage in milliseconds. This is the billing-relevant duration as reported by Actions. The `processing_request_conclusion` tag reflects whether the agent's "Processing Request" step actually executed and what its outcome was — use this to compute agent-only success rate (independent of user-defined workflow steps). Values: `not_reached` when the workflow job is unavailable or both Linux/Windows variants were skipped; otherwise the GitHub-reported step conclusion verbatim (typically `success`, `failure`, `cancelled`, or `timed_out`; `neutral`, `action_required`, and `stale` are also possible). For success-rate monitors, treat any non-`success` value as a failure. |
| `dynamic_workflow_step_duration` | Per-step duration | `on_workflow_run_completed.go` | step tags | Duration of individual workflow steps (e.g., checkout, agent run). Useful for identifying which step in the Actions workflow is slow. |

† **Standard tags**: `event_type`, `agent_type`, `custom_setup_steps`, `runs_on`, `async_sessions`

### 4b. New Metrics

| Metric | Formula | Emitted In | Tags | Description |
|---|---|---|---|---|
| `jobs.prepared_to_queued` | QueuedAt − PreparedAt | `jobservice.go` `UpdateJobForQueued` | standard | Time between Build completion and queue entry. Expected to be very small (sub-second) — it only covers the `UpdateJobForQueued` DB write and queue insertion. If this metric is unexpectedly large, it indicates a problem with the queue or database layer. |

### 4c. Fixed Metrics

| Metric | Change |
|---|---|
| `jobs.request_to_started_ms` | Now emitted for Hydro events too (previously REST/Twirp only) |
| `jobs.request_to_running` | Now emitted for Hydro events too (previously REST/Twirp only) |

---

## 5. Complete Split Timing Chain

After implementing the new metrics, the full lifecycle can be decomposed into
non-overlapping segments. Each segment represents a distinct phase where
different systems are responsible for the time spent:

```
Request ──────────────────────────────────────────────────────────────── Completion
  │                                                                         │
  │  sweagentd processing                                                   │
  │                             ├── prepared_to_queued ──┤               │
  │                             │   (DB + queue insert)     │               │
  │                                                         │               │
  │  aqueduct queue + executor                              │               │
  │                             ├──── queue_wait_duration_ms ────┤           │
  │                             │     (queue + executor work)    │           │
  │                                                              │           │
  │  GitHub Actions infrastructure                               │           │
  │                                                              ├─launched  │
  │                                                              │ _to_     │
  │                                                              │ started  │
  │                                                              │           │
  │  Agent runtime                                               │           │
  │                                                              │  ├─started│
  │                                                              │  │_to_    │
  │                                                              │  │running │
  │                                                              │           │
  │  Agent execution                                             │           │
  │                                                              ├──execution│
  │                                                              │  _duration│
  │                                                              │  _ms     │
  │                                                              │           │
  │  End-to-end (spans everything above)                         │           │
  ├────────────────── request_to_launched ─────────────────┤              │
  ├────────────────── request_to_started_ms ─────────────────────┤           │
  ├────────────────── request_to_running ─────────────────────────┼───┤       │
  ├────────────────────────── total_duration_ms ────────────────────────────┤
```

### How to read the split timing chain

The segments above are grouped by **who is responsible** for the time:

| Responsible System | Metric | What to investigate if slow |
|---|---|---|
| **sweagentd** | `prepared_to_queued` | Database or queue infrastructure issues (should be <1s) |
| **aqueduct + sweagentd** | `queue_wait_duration_ms` | Worker pool capacity, rate limiting, quota checks, workflow generation |
| **GitHub Actions** | `launched_to_started` | Runner availability, Actions scheduling, VM provisioning |
| **Agent runtime** | `started_to_running` | Repo clone speed, dependency installation, firewall setup |
| **Agent** | `execution_duration_ms` | LLM response times, tool execution, problem complexity |

### Derived calculations (no new metrics needed)

These can be computed from existing + new metrics in dashboards:

| Derived Metric | Calculation | What it tells you |
|---|---|---|
| Total pre-execution | `request_to_launched` | Everything under sweagentd's control before handing off to Actions |
| Actions + agent overhead | `launched_to_started` + `started_to_running` | Time from workflow dispatch to agent actually working on the problem |

---

## 6. What the Build Phase Includes

The `JobBuilder.Build()` method (`internal/jobservice/builder.go`) is where
sweagentd does the heavy lifting to prepare a job for execution. It performs
many operations, several of which involve external API calls that contribute
to latency. Understanding these steps helps diagnose slow Build phases.

The steps execute roughly in this order:

1. **Assignment lookup/creation** (DB) — Find or create the assignment that groups related jobs together (e.g., all jobs for a given issue or PR).
2. **Actor display login resolution** (Twirp → GitHub) — Resolve the human-readable login for the user who triggered the job.
3. **Rate limit check** (in-memory limiter) — Verify the actor hasn't exceeded the maximum number of queued jobs. This is a fast in-memory check.
4. **Model determination** (Twirp → Copilot API) — Determine which LLM model to use based on the user's request, available models, and feature flags.
5. **Problem statement building** (may fetch issue/PR content from GitHub) — Assemble the full problem statement the agent will work on. For PR comments/reviews, this fetches conversation history and code context.
6. **AI name generation** (Copilot API LLM call) — Generate human-readable names for the session, branch, and PR title using an LLM. This is one of the slower steps as it involves a full LLM inference call.
7. **Branch creation** (GitHub API — `CreateRef`) — Create the Git branch the agent will work on. May retry with alternative branch names if the first choice conflicts.
8. **Branch protection rules check** (GitHub API) — Verify the branch doesn't violate repository rules. If rules are violated, the job is finalized as failed.
9. **Pull request creation** (Twirp → GitHub) — Open a pull request for the agent's work (when applicable). Includes adding labels and linking the PR to the session.
10. **Session creation** (Copilot API) — Create a CAPI session to track the agent's progress and provide UX to users.
11. **Experiment assignment** — Assign A/B experiment variations for the job.
12. **Onboarding comment** (GitHub API) — Post a first-time-use onboarding comment on the PR if the user hasn't seen it before.
13. **Job persistence** (DB upsert) — Save the fully-built job to the database.

The Build phase duration can be derived from `PreparedAt − RequestStartedAt`. For
sub-phase breakdowns within Build, use the existing OpenTelemetry traces
(`jobservice.BuildJob` span and child spans).

---

## 7. What the Executor Phase Includes

After a job is dequeued by `jobexecutor.ProcessJob()`, the executor performs
several steps before submitting the workflow to Actions. This work is captured
within `queue_wait_duration_ms` (LaunchedAt − QueuedAt) alongside the actual
queue wait time. Understanding these steps helps diagnose why
`queue_wait_duration_ms` might be elevated even when the queue itself isn't
backed up.

The executor performs these steps in order:

1. **Job hydration from DB** (`GetJobQueuedForExecutionWithNonce`) — Load the full job record and its security nonce from the database.
2. **Custom agent config validation** — Check if the custom agent configuration is valid. Invalid configs cause the job to be cancelled immediately.
3. **Permission check** (`GetUserPermissionsForRepositoryByID`) — Verify the triggering user still has write access to the repository. Users may have lost access between job creation and execution.
4. **PR state validation** — For PR-related jobs, check if the pull request is still open. Closed PRs cause the job to be cancelled.
5. **Previous session ID lookup** — Find session IDs from prior completed jobs for the same assignment, so the agent has context about previous work.
6. **Quota check** (`checkQuota` — Twirp call) — Verify the user has sufficient premium quota to run the agent. If not, the job is finalized as failed.
7. **Launch options construction** (`launchOptsForJob`) — Build the full set of options needed to launch the agent, including:
   - Custom agent resolution from the database record
   - Experiment string assembly
   - Repository configuration lookup (`IsAgentEnabled` Twirp call for snippy blocking mode, validation tools)
8. **`LaunchAgent()`** — The final step that generates and submits the workflow:
   - Environment variable generation (callback URLs, API URLs)
   - Secrets and variables fetching from GitHub API (`GetCopilotEnvironmentSecretsAndVariables`)
   - Firewall configuration and allow-list assembly
   - Feature flag resolution for the workflow
   - MCP (Model Context Protocol) settings
   - Setup steps file fetch and processing (`copilot-setup-steps.yml`)
   - Workflow YAML template rendering
   - **`CreateDynamicWorkflowRun` API call** — the actual dispatch to GitHub Actions

The total executor phase time is captured by `queue_wait_duration_ms`
(LaunchedAt − QueuedAt). This metric conflates actual queue wait with executor
processing, but in practice the executor processing is typically much shorter
than queue wait time under normal conditions.

---

## 8. Tags

All job lifecycle metrics use a consistent tag set for filtering and grouping:

| Tag | Values | Description |
|---|---|---|
| `event_type` | `issue_created`, `pull_request_comment`, `pull_request_review`, `code_scanning_alerts_assignment`, `api_call_received`, `slack` | What triggered the job |
| `agent_type` | `fix`, `fix-pr-comment`, `task` | The category of work |
| `custom_setup_steps` | `true`, `false` | Whether a `copilot-setup-steps.yml` was used |
| `runs_on` | `ubuntu-latest`, `other` | Runner label category |
| `async_sessions` | `true`, `false` | Whether async session management is enabled |
| `was_delayed` | `true`, `false` | Whether the job was ever intentionally delayed due to rate limiting or concurrency limits (see below) |
| `terminal_state` | `completed`, `failed`, `cancelled`, `timed_out` | (completion metrics only) Final job status |

### Delay Tagging

The `was_delayed` tag identifies jobs that were requeued at least once before
execution due to rate limiting or concurrency limits. When a job is picked up
from the execution queue by the aqueduct handler, it checks:

1. **Rate limits** — Has the repository/owner exceeded the API call rate limit?
2. **Concurrent job limits** — Is the actor already running the maximum number
   of concurrent jobs?

If either check triggers, the job is requeued with a delay (90 seconds for
concurrency limits, variable for rate limits). The aqueduct `AgentJob` message
tracks a `RequeueCount` field that increments with each requeue.

When the job is eventually processed (no longer delayed), the executor sets
`WasDelayed = true` on the `Job` struct if `RequeueCount > 0`. This field is
persisted to the database so that all subsequent metrics — including those
emitted during callbacks and at completion — carry the `was_delayed` tag.

This tag is useful for:
- **Filtering dashboards** to see latency distributions for delayed vs
  non-delayed jobs separately
- **Understanding the impact of rate/concurrency limiting** on end-to-end
  job latency
- **Identifying whether elevated `queue_wait_duration_ms` is caused by
  intentional delays** vs infrastructure issues

---

## 9. Agent-Side Timing

The agent runtime reports additional timing events via callbacks:

| Metric | Source | Description |
|---|---|---|
| `agent.runtime_timing_duration_ms` | Agent callback (`agentcallback/telemetry.go`) | Duration of specific runtime phases (allowlisted: `launch.firewall_mkcert_install`, `launch.firewall_prepare`, `runtime.initial_clone`) |
| `agentcallback.request_duration` | Callback handler (`agentcallback/handler.go`) | Duration of individual callback HTTP requests |

---

## 10. Gaps Considered but Deferred

| Potential Metric | Reason Deferred |
|---|---|
| **Executor processing duration** (dequeue → `LaunchAgent` call) | Would require a new timestamp when the executor picks up the job from the queue. Currently conflated within `queue_wait_duration_ms`. Could be useful if we need to separate actual queue wait from executor processing, but in practice executor work is fast relative to queue wait. |
| **Workflow submission duration** (timer around `CreateDynamicWorkflowRun`) | Would isolate the Actions API call latency. Decided against adding it as it's a small subset of `queue_wait_duration_ms` and the API call is typically fast. Can be added later if Actions API latency becomes a concern. |
| **Per-step Build() timing** (e.g., branch creation, PR creation, AI naming separately) | Already covered by OpenTelemetry spans within the `jobservice.BuildJob` trace. Adding DD metrics for each sub-step would create high metric cardinality without clear dashboard value. |
| **Hydro event-to-dispatch latency** | Hydro consumer lag is tracked at the infrastructure level. The time between event production and consumption is not within sweagentd's control. |
| **API queue wait** (for async REST/Twirp jobs: `QueueJobForProcessing` → `Process` pickup) | This is the time an APIJob sits in the first aqueduct queue before being built. Could be useful but is a separate concern from the execution pipeline and would require another timestamp. Can be added later if the two-phase flow becomes a bottleneck. |
