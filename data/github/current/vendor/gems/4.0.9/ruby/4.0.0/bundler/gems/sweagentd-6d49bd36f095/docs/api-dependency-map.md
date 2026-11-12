# API Dependency Map

This document maps every API endpoint and job handler in sweagentd to the external APIs/services they call and the credentials/tokens used for each call. It is intended to support security audits and architecture reviews.

> **See also:** [E2E Job Data Flow Analysis](./e2e-job-data-flow.md) — quantified per-job call counts and RPS breakdown derived from this map ([#11571](https://github.com/github/sweagentd/issues/11571))

---

## Client / Credential Types

### GitHub REST + GraphQL Client (`internal/github/github.go`, `factory.go`, `transport.go`)

The `github.Client` wraps `google/go-github` (REST) and `shurcooL/githubv4` (GraphQL). It is constructed by `ClientFactory`.

**Three token modes:**

| Factory Method | Token Type | Use Case |
|---|---|---|
| `NewClientForUser(token, userID, app)` | User/OAuth token (supplied by the caller) | User-facing API calls, permission checks using the caller's identity |
| `NewClientFromRepo(ctx, app, repoID, repoOwnerID)` | Installation/S2S token (minted via `SweagentdAPI().MintServerToServerTokenForRepo`) | Server-side GitHub operations scoped to the app installation on that repo |
| `NewClientForRepo(ctx, app, repo)` | Installation/S2S token (same mechanism) | Same as above; accepts a `sweagentd.Repository` value |
| `NewClientFromRepoName(ctx, app, repoName, ownerName, userID)` | Installation/S2S token (resolves repo via `RepositoriesAPI`, then mints token) | When only owner/repo names are known |

**S2S token minting flow:** `tokens.GetServerToServerTokenByRepoID` → `SweagentdAPI().MintServerToServerTokenForRepo` (GitHub internal Twirp → github/github monolith).

Tokens are cached per `(appID, repoID, ownerID)` during the lifetime of a request using `tokens.Cache`.

The `ClientRoundTripper` (`transport.go`) injects `User-Agent: sweagentd`, forwarded request IDs, tenant headers (for Proxima), and `X-Forwarded-For` / `X-Real-IP` on every outbound GitHub REST/GraphQL request.

A feature flag (`CopilotSWEAgentUseInternalAPI`) toggles between the public GitHub API base URL and the internal GitHub API base URL.

Outbound GitHub API metrics (`sweagentd.github.api.request`, `.error`, `.rate_limit_remaining`, `.rate_limit_exceeded`) are tagged by `api_target` and `auth_type` when `coding_agent_api_metric_tags` is enabled. Use those tags to split full-sample traffic by public/internal REST, GraphQL, CAPI, and Twirp surfaces, and by installation/HMAC/user/integration auth.

---

### GitHub Internal Twirp Client (`internal/githubtwirp/client.go`)

A multi-service Twirp client authenticated with **HMAC signatures** (using `GitHubTwirpHMACKey` / `LimiterTwirpHMACKey` / `BillingClientHMACKey` from config). All sub-services share the same HMAC-signed HTTP transport.

Exposes the following sub-APIs (all called via the internal GitHub monolith or related internal services):

| Sub-API | Interface | Internal service / URL |
|---|---|---|
| `UserDetailAPI()` → `CopilotUserDetailAPI` | `copilot-twirp/proto/users/v1` | `GitHubTwirpAPIURL` |
| `SweagentdAPI()` → `SweagentdAPI` | `sweagentd/proto/sweagentd/v1` | `GitHubTwirpAPIURL` |
| `LimiterAPI()` → `CopilotLimiterAPI` | `copilot-twirp/proto/limiter/v1` | `LimiterTwirpAPIURL` |
| `AuthorizationAPI()` → `AuthorizationAPI` | `copilot-api/proto/twirp/core/v1` | `GitHubTwirpAPIURL` |
| `RepositoriesAPI()` → `RepositoriesAPI` | `github-proto/gen/go/repositories/v1` | `GitHubTwirpAPIURL` |
| `BillingClient()` | `billing-platform/clients/go/v1` | `BillingClientURL` |

**Key helper methods on `ClientInterface`:**

- `IsAgentEnabled(agentID, userID, repositoryID)` → calls `SweagentdAPI().ConfigurationForRepository` — checks Copilot enablement and returns repo-level config.
- `GetCopilotUserDetails(userID)` → calls `UserDetailAPI().GetCopilotUserDetails` on cache miss — returns Copilot subscription plan, feature flags, etc. Results are memoized in context and cached in Redis for 5 minutes.
- `GetCustomerID(userID)` → calls `GetCopilotUserDetails` then extracts customer ID.
- `IsMemoryEnabled(userID)` → reads `GetCopilotUserDetails` data (usually context/Redis cached) and checks memory feature.
- `GetRepoById(id)` → calls `RepositoriesAPI().FindRepositories`.
- `GetRepoByName(owner, name)` → calls `RepositoriesAPI().FindRepositoriesByName`.
- `GetInstallationInfo(appID, repoID)` → calls `SweagentdAPI()` (used in token minting).
- `TokenHasAccess(user, rules)` → calls `AuthorizationAPI().BatchControlAccess` — checks token permissions against resource-action pairs.
- `CheckPremiumQuota(ownerID, repoID, userID)` → calls `GetCopilotUserDetails` + `LimiterAPI().GetQuotaRemaining` — checks if user has sufficient Copilot premium quota.

---

### CAPI Client (`internal/capi/capi.go`)

The **GitHub Copilot API** client handles AI model interactions and session management.

**Two authentication modes:**

| Client Type | Credential | Usage |
|---|---|---|
| `HmacClient` | HMAC secret (`CAPIHMACKey` from config) + `Copilot-Integration-Id` header | Server-side `ChatCompletions` (for stacked PR title/intent generation), `ListCodingAgentModels`, `CreateModelSession` |
| `UserClient` (via `NewSessionClient`) | User token (OAuth/installation token passed at creation time) | Session lifecycle: `CreateSession`, `GetSession`, `UpdateSession` |

The `UserTransport` sets `Authorization: Bearer <token>` on all requests. The `HmacTransport` sets `X-GitHub-HMAC` on all requests.

Both transports add `Copilot-Integration-Id`, `X-GitHub-Api-Version`, `X-GitHub-Request-Id`, and tenant headers.

For `CreateModelSession` and `ListCodingAgentModels`, the `HmacClient` is used directly (HMAC auth). For session management, a `UserClient` is created per-job with the actor's token.

---

### Aqueduct Client (`internal/aqueduct/client.go`)

Job queue service. Authenticated with **Aqueduct API Key** (environment-specific: `AqueductAPIKey`, `AqueductStagingAPIKey`, etc.). Used to enqueue jobs (`APIJob`, `AgentJob`, `EventJob`) for asynchronous processing.

---

### Experiments Client (`internal/experiments/experiments.go`)

Calls the **Microsoft ExP (experimentation) API** (`ExperimentationAPIURL`) over plain HTTP. No authentication headers are added by the client itself. The `ExpTransport` adds a `X-VSCode-ExtensionName` header.

Calls `NewTrafficFiltersDefaults` which internally calls `githubtwirp.ClientInterface.GetRepoById` and `GetCopilotUserDetails` to populate traffic filters (repo visibility, user kind) before the ExP HTTP call.

---

### Token Minting (`internal/agenticapp/mint_token.go`)

Used for **agentic app token minting** (GitHub App tokens):

- `mintToken(ctx, ghtwirp, client, tokenReq)`: Calls `SweagentdAPI()` (via `ghtwirp`) to resolve repo ID, then calls GitHub REST API `Apps.FindRepositoryInstallationByID` + `Apps.CreateInstallationToken` using an **app JWT token** (`client` is a `*gg.Client` authenticated with an app private key).
- `mintTokenForGlobalApp(ctx, client, tokenReq)`: Calls `POST /app/global/access_tokens` on the GitHub REST API using an **app JWT token** to mint a global (non-repo-scoped) installation token.

---

## Twirp RPC Endpoints (JobsAPI)

The Twirp server is implemented in `internal/twirpserver/`. All endpoints share the `Server` struct which holds: `ghf` (GitHub client factory), `ghTwirp` (GitHub internal Twirp client), `jobStore` (DB), `jobService` (business logic), `ffClient` (feature flags), `appProvider` (agentic app registry), `jobExecutor` (job executor).

---

### `CreateJob`

**File:** `internal/twirpserver/twirpserver.go`

**Purpose:** Creates an assignment + a job in one call. Used by GitHub.com / integrations.

**External calls:**

1. **Quota check** (conditional, skipped for quota-exempt apps):
   - `CheckQuota(ctx, ghTwirp, ...)` →
     - `ghTwirp.GetCopilotUserDetails(actorID)` → **GitHub internal Twirp** (`UserDetailAPI.GetCopilotUserDetails`), HMAC auth
     - `ghTwirp.LimiterAPI().GetQuotaRemaining(...)` → **Limiter Twirp**, HMAC auth
2. **GitHub client creation (installation token)**:
   - `ghf.NewClientFromRepo(ctx, CopilotApp, repoID, ownerID)` → calls `SweagentdAPI().MintServerToServerTokenForRepo` → **GitHub internal Twirp**, HMAC auth
3. **Get repository** (REST, installation token):
   - `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API** `GET /repositories/{id}`, installation token
4. **Create assignment** (`createAssignment`):
   - Writes to the database (no external API call)
5. **Look up existing PR** (if `HeadRef` provided and feature flag enabled):
   - `github.LookupExistingPRForHeadRef(ctx, gh, ...)` → `gh.GetPullRequests(...)` → **GitHub REST API** `GET /repos/{owner}/{repo}/pulls`, installation token
6. **`jobService.CreateJobForAssignment(...)`** — see [jobservice.CreateJobForAssignment](#jobservicecreatejobforassignment) for full call trace.

---

### `CreateJobForAssignment`

**File:** `internal/twirpserver/create_job_for_assignment.go`

**Purpose:** Creates a job for a pre-existing assignment.

**External calls:**

1. **Quota check** (same as `CreateJob`):
   - `CheckQuota(ctx, ghTwirp, ...)` → same Twirp calls as above
2. **`jobService.CreateJobForAssignment(...)`** — see [jobservice.CreateJobForAssignment](#jobservicecreatejobforassignment).

---

### `CreateAssignment`

**File:** `internal/twirpserver/create_assignment.go`

**Purpose:** Creates an empty assignment for a repository.

**External calls:**

1. **Quota check** (if `actorID` provided and feature flag enabled):
   - `CheckQuota(ctx, ghTwirp, ...)` → `GetCopilotUserDetails` + `LimiterAPI().GetQuotaRemaining`, HMAC auth
2. **GitHub client creation (installation token)**:
   - `ghf.NewClientFromRepo(ctx, CopilotApp, repoID, ownerID)` → `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth
3. **Get repository** (REST, installation token):
   - `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API** `GET /repositories/{id}`, installation token
4. DB write (no external call).

---

### `CreateCommand`

**File:** `internal/twirpserver/create_command.go`

**Purpose:** Adds a user command to an existing job (for multi-turn conversations).

**External calls:**

1. DB read: `jobService.GetJobByID(...)` (no external API call).
2. **Agent enablement check**:
   - `ghTwirp.IsAgentEnabled(ctx, appID, actorID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
3. **User details**:
   - `ghTwirp.GetCopilotUserDetails(ctx, actorID)` → `UserDetailAPI.GetCopilotUserDetails`, HMAC auth
4. **Quota check** (for non-exempt apps):
   - `CheckQuota(ctx, ghTwirp, ...)` → `GetCopilotUserDetails` (cached) + `LimiterAPI().GetQuotaRemaining`, HMAC auth
5. DB write: `jobService.CreateCommandForJob(...)` (no external API call).

---

### `CancelJob`

**File:** `internal/twirpserver/cancel_job.go`

**Purpose:** Cancels an in-progress job by its session ID.

**External calls:**

1. DB read: `jobService.GetJobBySessionID(...)` (no external API call).
2. **GitHub client creation (installation token)**:
   - `ghf.NewClientFromRepo(ctx, app, repoID, ownerID)` → `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth
3. **Get repository** (REST, installation token):
   - `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API** `GET /repositories/{id}`, installation token
4. **`jobExecutor.CancelJob(...)`**:
   - `gh.CancelWorkflowRunByID(ctx, owner, repo, runID)` → **GitHub REST API** `POST /repos/{owner}/{repo}/actions/runs/{run_id}/cancel`, installation token (if a workflow run is in progress)
   - DB updates (job status).

---

### `ListJobsForPullRequest`

**File:** `internal/twirpserver/twirpserver.go`

**Purpose:** Returns all jobs for a pull request.

**External calls:** Only DB reads (`jobStore.GetAssignmentForPR`, `jobStore.GetJobsForAssignment`). No external API calls.

---

### `GetJobBySessionID`

**File:** `internal/twirpserver/twirpserver.go`

**Purpose:** Retrieves a job by its session ID.

**External calls:** Only DB reads (`jobService.GetJobBySessionID`). No external API calls.

---

### `UpdateAssignment`

**File:** `internal/twirpserver/update_assignment.go`

**Purpose:** Patches an assignment (e.g., links a PR to an assignment).

**External calls:** Only DB reads and writes (`jobStore.GetAssignment`, `jobStore.PatchAssignment`). No external API calls.

---

## HTTP API Endpoints

### Job API Handler (`internal/api/jobapi/handler.go`)

Routes registered at `/`, `/v0`, and `/v1`.

#### Middleware / Authorization (applied to all routes)

Every route goes through `Handler.middleware` → `Handler.authorizeUser`:

1. Feature-flag disallow check (no external call).
2. **Token access verification** (`verifyTokenAccess`):
   - `ghTwirp.TokenHasAccess(ctx, user, rules)` → `AuthorizationAPI().BatchControlAccess`, HMAC auth
   - Checks `pull`, `push`, `create_pull_request`, `write_actions` actions against the target repository.
3. **User permission check** (REST, user token):
   - `cf.NewClientForUser(userToken, userID, CopilotApp)` → creates a user-token GitHub REST client
   - `userTokenGH.GetUserPermissionsForRepository(ctx, owner, repo, login)` → **GitHub REST API** `GET /repos/{owner}/{repo}/collaborators/{username}/permission`, **user/OAuth token**
4. **Get repository** (REST, user token):
   - `userTokenGH.GetRepository(ctx, owner, repo)` → **GitHub REST API** `GET /repos/{owner}/{repo}`, **user/OAuth token**

---

#### `POST /jobs/{owner}/{repo}` — `HandleNewJob` (sync, non-versioned / v0)

**Purpose:** Creates and immediately queues a job for execution.

**External calls (beyond middleware):**

1. **GitHub client selection** (feature-flag-dependent):
   - If `CopilotSWEAgentNewJobUseClientToken` enabled: `cf.NewClientForUser(userToken, ...)` → **user token**
   - Otherwise: `cf.NewClientFromRepoName(ctx, app, repoName, ownerName, userID)` → resolves repo via `RepositoriesAPI().FindRepositoriesByName` then mints installation token → **installation token**
2. **Agent enablement check**:
   - `ghTwirp.IsAgentEnabled(ctx, agentID, userID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
3. **Base ref existence check** (if provided):
   - `h.spokes.CheckForExistingRefs(ctx, repoID, refs)` → **Spokes service** (internal)
4. **Existing PR lookup** (if `HeadRef` provided and feature flag enabled):
   - `gh.GetPullRequests(...)` → **GitHub REST API** `GET /repos/{owner}/{repo}/pulls`, user or installation token
5. **Workflow-modification access check** (feature-flag-gated by `copilot_swe_agent_scope_git_token_workflows`, `resolveWorkflowAccess`):
   - `ghTwirp.TokenHasAccess(ctx, user, [{Action: "write_workflows", ResourceType: "Repository", RepositoryNWO: ...}])` → `AuthorizationAPI().BatchControlAccess`, HMAC auth
   - Result is persisted on the job and forwarded to the dynamic workflow as `COPILOT_AGENT_GIT_TOKEN_INCLUDE_WORKFLOWS` so dotcom can scope `GITHUB_COPILOT_GIT_TOKEN`'s `workflows:write` permission. Privileged apps skip this call. Fails closed on error.
6. **Build job** (`jobService.NewJobBuilder(...).Build()`):
   - See [jobservice.JobBuilder.Build](#jobservicejobbuilder-build) for full call trace.
7. **Queue job for execution**:
   - `jobService.QueueJobForExecution(ctx, job)` → `aqueductClient.Send(AgentJob)` → **Aqueduct**, API key auth

---

#### `POST /jobs/{owner}/{repo}` — `HandleNewJobAsync` (v1)

Identical to `HandleNewJob` but queues an `APIJob` (processed asynchronously) instead of an `AgentJob`:

- `jobService.QueueJobForProcessing(ctx, job)` → `aqueductClient.Send(APIJob)` → **Aqueduct**, API key auth

---

#### `POST /jobs/{owner}/{repo}/{job}/cancel` and `POST /jobs/{owner}/{repo}/session/{session}/cancel` — `HandleCancelJob`

**External calls (beyond middleware):**

1. **Resolve repo IDs**:
   - `ghTwirp.GetRepoByName(ctx, owner, repo)` → `RepositoriesAPI().FindRepositoriesByName`, HMAC auth
2. DB read: job lookup.
3. **Agent enablement check** (feature-flag-dependent):
   - `ghTwirp.IsAgentEnabled(ctx, agentID, userID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
4. **GitHub client selection**:
   - `cf.NewClientForUser(userToken, ...)` or `cf.NewClientFromRepoName(...)` → user or installation token
5. **`jobExecutor.CancelJob(ctx, gh, job, owner, repo)`**:
   - `gh.CancelWorkflowRunByID(...)` → **GitHub REST API** `POST /repos/{owner}/{repo}/actions/runs/{run_id}/cancel`, installation or user token

---

#### `GET /jobs/{owner}/{repo}/{job}`, `GET /jobs/{owner}/{repo}/{job}/status`, `GET /jobs/{owner}/{repo}/session/{session}` — `HandleGetJobByIDOrSessionID`

**External calls (beyond middleware):**

1. **Resolve repo IDs**:
   - `ghTwirp.GetRepoByName(ctx, owner, repo)` → `RepositoriesAPI().FindRepositoriesByName`, HMAC auth
2. DB read: job lookup.
3. **Agent enablement check** (feature-flag-dependent):
   - `ghTwirp.IsAgentEnabled(ctx, agentID, userID, repoID)`, HMAC auth
4. GitHub client creation (optional, based on feature flag): user or installation token.
5. DB read: workflow run lookup for response hydration.

---

#### `GET /jobs/{owner}/{repo}/pulls/{prNumber}` — `HandleListJobsForPullRequest`

**External calls (beyond middleware):**

1. **Resolve repo IDs**:
   - `ghTwirp.GetRepoByName(ctx, owner, repo)` → `RepositoriesAPI().FindRepositoriesByName`, HMAC auth
2. DB read: jobs for PR.
3. **Agent enablement check** (for first job in list, feature-flag-dependent):
   - `ghTwirp.IsAgentEnabled(ctx, agentID, userID, repoID)`, HMAC auth

---

#### `GET /jobs/{owner}/{repo}/enabled` — `HandleCheckEnablement`

**Purpose:** Pre-flight check: verifies agent enablement and branch rules.

**External calls (beyond middleware):**

1. **Agent enablement check**:
   - `ghTwirp.IsAgentEnabled(ctx, agentID, userID, repoID)`, HMAC auth
2. **GitHub client** construction:
   - `cf.NewClientForUser(userInfo.TokenInfo.Token, userInfo.ID, agent)` — forwards the **caller's user/OAuth token** directly to the GitHub REST API. No installation token is minted for this handler.
3. **Branch rules check** (`jobService.CheckRules`):
   - `gh.GetActionsPermissions(ctx, owner, repo)` → **GitHub REST API** `GET /repos/{owner}/{repo}/actions/permissions`, user token
   - `gh.ListRepositoryRulesForBranch(ctx, ...)` → **GitHub REST API** `GET /repos/{owner}/{repo}/rules/branches/{branch}`, user token
   - `SweagentdAPI().IsBypassActor(ctx, req)` → **GitHub internal Twirp**, HMAC auth (checks if actor can bypass branch protection)

---

### Agent HTTP Handler (`internal/agent/agenthttp/handler.go`)

Routes registered under `/agent/`. These endpoints are called by the **agent runtime** (execution environment) using an OIDC token or S2S token.

#### `GET /agent/jobs/{jobID}` — `getJob`

**Purpose:** Returns full job configuration to the running agent.

**External calls:**

1. **Authorization** (OIDC/S2S token validation, internal).
2. **Agent enablement check** (unless S2S token or feature flag to skip):
   - `twirp.IsAgentEnabled(ctx, appID, userID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
3. DB read: job, assignment.
4. **List custom agents** for the repo (internal DB/store — no external API).
5. **List skills** (if feature flag enabled):
   - `skillsSvc.ListSkills(ctx, owner, repo, ...)` — DB read, no external API for org/enterprise skills.
6. **Organization custom instructions** — internal service, no external API.
7. **Load plugin settings** (if feature flag enabled) — DB read.
8. **CAPI model session token** (if `shouldMintModelSessionToken` — auto-mode experiment):
   - `capiClient.CreateModelSession(ctx, userID, modelHints, "")` → **CAPI** `POST /v1/copilot/model-sessions`, HMAC auth

---

#### `POST /agent/jobs/{jobID}/progress` / `GET /agent/jobs/{jobID}/progress` — `createProgress` / `getProgress`

DB reads and writes only. No external API calls.

---

#### `GET /agent/jobs/{jobID}/agent` — `getAgent`

Returns agent/custom-agent configuration. DB reads only. No external API calls.

---

### Agent Callback Handler (`internal/agentcallback/handler.go`)

Routes: `POST /agent/callback` (legacy). Called by the agent runtime to report job updates.

#### `HandleCallback`

**Purpose:** Processes job status updates from a running agent.

**External calls:**

1. **Agent enablement check** (for non-S2S tokens):
   - `ghTwirp.IsAgentEnabled(ctx, appID, userID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
2. DB read: `jobService.GetJobByID(...)`.
3. **`jobManager.HandleJobUpdate`** dispatches to one of:
   - `handleProgress` — DB writes, no external API.
   - `handleError` — `jobService.UpdateFromExecutionResult` (DB write) + `jobService.UpdateSession` → **CAPI** `PUT /v1/copilot/sessions/{id}`, user token (if session exists).
   - `handleResult` / `handleFixResult`:
     - `clients.NewClientForRepo(ctx, app, job)` → mints installation token via `SweagentdAPI()`, HMAC auth
     - `ghclient.UpdatePullRequest(ctx, repoID, pr)` → **GitHub REST API** `PATCH /repositories/{id}/pulls/{number}`, installation token
     - `ghclient.GetPullRequest(ctx, repoID, number)` → **GitHub REST API**, installation token
   - `handleFixPRCommentResult`:
     - `clients.NewClientForRepo(...)` → installation token
     - `ghclient.UpdateComment(ctx, owner, repo, commentID, body)` → **GitHub REST API** `PATCH /repos/{owner}/{repo}/issues/comments/{id}`, installation token
     - `ghclient.CreateComment(ctx, repoID, prNumber, body)` → **GitHub REST API** `POST /repositories/{id}/issues/{number}/comments`, installation token
   - `handleTaskResult` — DB updates, session update via CAPI (user token).
   - `handleCommentReply`:
     - `clients.NewClientForRepo(...)` → installation token
     - `ghclient.GetPullRequestContext(ctx, nodeID, number, ...)` → **GitHub GraphQL API** (GQL query), installation token
     - `ghclient.CreateCommentInReplyTo(...)` → **GitHub REST API**, installation token
     - `ghclient.UpdateComment(...)` → **GitHub REST API**, installation token
     - `ghclient.CreateComment(...)` → **GitHub REST API**, installation token
   - `handlePartialResult`:
     - `clients.NewClientForRepo(...)` → installation token
     - DB writes.
   - `handleCheckQuota`:
     - `CheckPremiumQuota(...)` → `GetCopilotUserDetails` + `LimiterAPI().GetQuotaRemaining`, HMAC auth
4. `jobService.UpdateFromExecutionResult(ctx, job, status, runningAt)` → DB write + `jobService.UpdateSession` → **CAPI**, user token.

---

### Memory HTTP Handler (`internal/memory/memoryhttp/memory_handler.go`)

Routes registered under `/memory/`. Handles long-term agent memory storage.

#### Authorization (all routes)

The `authorize` method:

1. **Token access check**:
   - `ghTwirp.TokenHasAccess(ctx, userInfo, rules)` → `AuthorizationAPI().BatchControlAccess`, HMAC auth
   - Checks `pull` and `push` (or `pull` only for read) against the repository.
2. **Repository info and permissions**:
   - `ghFactory.NewClientFromRepoName(ctx, CopilotApp, repo, owner, userID)` → installation token via `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth
   - `gh.GetUserPermissionsForRepositoryByID(ctx, repoID, username)` → **GitHub REST API** `GET /repositories/{id}/collaborators/{login}/permission`, installation token
   - Fallback: `ghFactory.NewClientForUser(userToken, ...)` → user token for `GetUserPermissionsForRepositoryByID`.
3. **Memory enabled check** (for memory-specific routes):
   - `ghTwirp.IsMemoryEnabled(ctx, userID)` → reads cached `UserDetailAPI.GetCopilotUserDetails` data when available, then checks `copilot_memory`.

#### `POST /memory` — `HandleCreateMemory`
DB write (memory store). No additional external API calls beyond auth.

#### `GET /memory/search` — `HandleSearchMemories`
DB read (vector search). No additional external API calls beyond auth.

#### `GET /memory/recent` — `HandleGetRecentMemories`
DB read. No additional external API calls beyond auth.

#### `GET /memory/top` — `HandleGetTopMemories`
DB read. No additional external API calls beyond auth.

#### `DELETE /memory/{id}` — `HandleDeleteMemory`
DB write. No additional external API calls beyond auth.

#### `POST /memory/{id}/vote` — `HandleVoteMemory`
DB write. No additional external API calls beyond auth.

#### `DELETE /memory` (batch) — `HandleDeleteMemories`
DB write. No additional external API calls beyond auth.

#### `DELETE /memory/all` — `HandleDeleteAllMemories`
DB write. No additional external API calls beyond auth.

#### `GET /memory/enabled` — `HandleCheckMemoryEnabled`
- `ghTwirp.IsMemoryEnabled(ctx, userID)` → reads cached `UserDetailAPI.GetCopilotUserDetails` data when available, then checks `copilot_memory`

#### `GET /memory/prompt` — `HandleGetPrompt`
DB read + experiment assignment lookup. No external API calls beyond auth.

---

### Agent Sync Handler (`internal/agentsync/handler.go`)

A **Hydro message handler** (not an HTTP endpoint). Processes `agents_updated` Hydro events to sync custom agent configuration.

**External calls:**

- On enterprise agent repo detection: `TwirpEnterpriseResolver.IsEnterpriseAgentRepo(ctx, ownerID)` → calls `sweagentdTwirp.SweagentdAPI().GetEnterpriseAgentRepoForOrganization(...)` → **GitHub internal Twirp**, HMAC auth
- DB writes for custom agent configuration (no other external API calls).

---

### Agent Cleanup Handler (`internal/agentcleanup/handler.go`)

Route: `POST /agent/cleanup`. Called by the GitHub Actions runner on workflow completion.

#### `HandleCleanup`

**Purpose:** Processes cleanup requests after a workflow run completes (e.g., revokes tokens, marks jobs done).

**External calls:**

1. DB read: `jobs.GetJobForComputeID(...)`.
2. **Agent enablement check** (for non-S2S tokens):
   - `ghTwirp.IsAgentEnabled(ctx, appID, userID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
3. Further action dispatched to the registered cleanup delegate (typically `agentcallback.Handler.HandleCleanup`) — see agent callback handler above.

---

## Aqueduct Job Handlers

### ApiJob Handler (`internal/aqueduct/jobs/apijob/handler.go`)

**Queue:** `api-job`

**Purpose:** Processes `APIJob` messages (queued by `HandleNewJobAsync`). Calls `jobservice.Process(ctx, apiJob)` which orchestrates the full job creation pipeline.

**External calls via `jobService.Process`:**

1. DB read: `GetJobQueuedForProcessing` → fetches assignment and job.
2. **`jobService.CreateJobForAssignment`** (the full pipeline):
   - See [jobservice.CreateJobForAssignment](#jobservicecreatejobforassignment) for complete call trace.

---

### EventJob Handler (`internal/aqueduct/jobs/eventjob/handler.go`)

**Queues:** `event-job`, `event-job-trigger`, `event-job-background`

**Purpose:** Processes GitHub-originated Hydro events (delivered via Kafka, **not** direct HTTP webhooks) by dispatching to `events.EventsHandler`.

**External calls:** All calls are made within the `events.Handler` — see [Event Handlers](#event-handlers) section below.

---

### AgentJob Handler (`internal/aqueduct/jobs/agentjob/handler.go`)

**Queue:** `agent-job`

**Purpose:** Dequeues an `AgentJob` and calls `jobexecutor.ProcessJob` to launch the agent.

**External calls:**

1. **Rate limit check**:
   - `rateLimiter.DelayProcessing(ctx, agentID, ownerID, repoID, ...)` → internal in-memory limiter (checks cached GitHub API rate limits; may trigger `AltClientFactory.RateLimitsForRepo` → `SweagentdAPI().MintServerToServerTokenForRepo` + **GitHub REST API** `GET /rate_limit`, installation token).
2. **`executor.ProcessJob(ctx, agentJob)`** — see [AgentJobExecutor.ProcessJob](#agentjobexecutorprocessjob).

---

## jobservice Internal Flows

### `jobservice.CreateJobForAssignment`

Called from Twirp (`CreateJob`, `CreateJobForAssignment`), HTTP API (`HandleNewJob`, `HandleNewJobAsync`), and `apiJob.Process`.

**External calls:**

1. DB read: assignment and existing jobs.
2. **`setupAssignmentContext`**:
   - `twirp.IsAgentEnabled(ctx, appID, actorID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth
   - `twirp.GetCopilotUserDetails(ctx, actorID)` → `UserDetailAPI.GetCopilotUserDetails`, HMAC auth
   - `ghf.NewClientFromRepo(ctx, agenticApp, repoID, ownerID)` → mints installation token via `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth
   - `gh.GetUserByID(ctx, actorID)` → **GitHub REST API** `GET /user/{id}`, installation token (to get actor user object)
   - `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API** `GET /repositories/{id}`, installation token
3. **Branch resolution** (`ResolveBranchConfig`) — DB/logic only.
4. **Custom agent lookup** (`setupCustomAgent` → `GetCustomAgent`):
   - For custom agents: reads from agent config store (DB). May call `gh.GetContents(...)` → **GitHub REST API** `GET /repos/{owner}/{repo}/contents/{path}`, installation token (to read `.github/copilot-agent.yml`).
5. **Model resolution** (`ResolveModel`):
   - `capi.ListCodingAgentModels(ctx, userID, actorType)` → **CAPI** `GET /v1/copilot/models`, HMAC auth
   - `twirp.GetCopilotUserDetails(ctx, actorID)` (cached) — to get Copilot plan for model selection
6. **Experiment assignment** (`getExperimentAssignment`):
   - `experiments.GetFeatureAssignment(...)` → **ExP HTTP API** (`ExperimentationAPIURL`), no credential header (uses traffic filters)
7. **Session creation** (`createSessionForJob`):
   - `GetSessionClient(ctx, agentID, job)`:
     - For org-billed: `tokens.GetTokenForJob(...)` → `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth → **CAPI** user token from this S2S token
     - For user-billed: `tokens.GetUserToServerToken(...)` → `SweagentdAPI().GetUserToServerToken(...)`, HMAC auth → **CAPI** user-to-server token
   - `sessionClient.CreateSession(ctx, sessionCreate)` → **CAPI** `POST /v1/copilot/sessions`, user/S2S token
8. **`JobBuilder.Build()`** — see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build).
9. **Queue job**: `queue.Send(AgentJob)` → **Aqueduct**, API key auth.

---

### `jobservice.JobBuilder.Build`

Called from `CreateJobForAssignment` and event handlers.

**External calls:**

1. `twirp.GetCopilotUserDetails(ctx, actorID)` → `UserDetailAPI.GetCopilotUserDetails`, HMAC auth (for display login / actor info)
2. **Branch creation** (if required):
   - `service.CreateEmptyCommit(ctx, gh, job)` → `spokes.CreateEmptyCommit(ctx, opts)` → **Spokes service** (internal, S2S)
   - `service.CreateBranch(ctx, gh, job, commitOID)` → `spokes.CreateBranch(ctx, opts)` → **Spokes service** (internal, S2S)
3. **Branch rules check** (`service.CheckRules`):
   - `gh.GetActionsPermissions(ctx, owner, repo)` → **GitHub REST API**, installation token
   - `gh.ListRepositoryRulesForBranch(ctx, ...)` → **GitHub REST API**, installation token
   - `twirp.SweagentdAPI().IsBypassActor(ctx, req)` → **GitHub internal Twirp**, HMAC auth
4. **PR creation** (for fix/task jobs with PR):
   - `service.OpenPullRequest(ctx, twirp.SweagentdAPI(), assignment, job, title, body)` → `sweagentdTwirp.SweagentdAPI().CreatePullRequest(ctx, req)` → **GitHub internal Twirp**, HMAC auth
   - Fallback to REST: `gh.CreatePullRequest(ctx, owner, repo, opts)` → **GitHub REST API**, installation token
   - Label adding: `gh.AddLabelsToIssueOrPR(ctx, ...)` → **GitHub REST API**, installation token
5. **Session update** (for queued state):
   - `sessionClient.UpdateSession(ctx, sessionID, update)` → **CAPI** `PUT /v1/copilot/sessions/{id}`, user/S2S token
6. **`githubtwirp.ResolveDisplayLogin`** → `twirp.GetCopilotUserDetails(ctx, userID)`, HMAC auth

---

### `AgentJobExecutor.ProcessJob`

**File:** `internal/jobexecutor/jobexecutor.go`

Called from the `agentjob.Handler`.

**External calls:**

1. DB read: job fetch + nonce.
2. **Permission check** (for non-org-actor jobs):
   - `gh.GetUserPermissionsForRepositoryByID(ctx, repoID, actorLogin)` → **GitHub REST API** `GET /repositories/{id}/collaborators/{login}/permission`, installation token
3. **Pull request state check** (if job has PR):
   - `gh.GetPullRequest(ctx, repoID, number)` → **GitHub REST API** `GET /repositories/{id}/pulls/{number}`, installation token
4. **Get repository**:
   - `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API** `GET /repositories/{id}`, installation token
5. **Quota check** (`checkQuota`):
   - `CheckPremiumQuota(...)` → `GetCopilotUserDetails` + `LimiterAPI().GetQuotaRemaining`, HMAC auth
   - On insufficient quota (with PR): `gh.RequestReviewers(ctx, owner, repo, prNumber, [actorLogin])` → **GitHub REST API**, installation token
6. **`launchOptsForJob`**:
   - `twirp.IsAgentEnabled(ctx, agentID, actorID, repoID)` → `SweagentdAPI().ConfigurationForRepository`, HMAC auth (retrieves snippy blocking mode and tool settings)
   - Custom agent resolution (may read `.github/copilot-agent.yml` via `gh.GetContents(...)`) → **GitHub REST API**, installation token
7. **`launchAgent`** → calls `launcher.LaunchAgent(opts)` which starts the GitHub Actions workflow:
   - `gh.CreateDynamicWorkflowRun(ctx, owner, repo, repoID, ...)` → **GitHub REST API** (internal/dynamic-workflow endpoint), installation token, authenticated with **HMAC** (`DynamicWorkflowsHMACKey`) in the request body.

---

## Event Handlers

All event handlers live in `internal/events/`. The `Handler` struct holds: `ghFactory` (GitHub client factory), `ghTwirp` (GitHub internal Twirp client), `jobService`, `appProvider`, `capiClient` (CAPI), etc.

Common GitHub client pattern: `ghFactory.NewClientForRepo(ctx, app, &event)` or `ghFactory.NewClientFromRepo(ctx, app, repoID, ownerID)` — **always mints an installation token** via `SweagentdAPI().MintServerToServerTokenForRepo`, HMAC auth.

---

### `OnIssueCreated` (`on_issue_created.go`)

Triggered when an issue is assigned to Copilot.

**External calls:**

1. `ghFactory.NewClientForRepo(ctx, app, &event)` → installation token
2. `gh.GetIssue(ctx, owner, repo, number)` → **GitHub REST API** `GET /repos/{owner}/{repo}/issues/{number}`, installation token
3. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
4. `gh.AssignToIssue(ctx, owner, repo, issueNumber, copilotBotLogin)` → **GitHub REST API** `POST /repos/{owner}/{repo}/issues/{number}/assignees`, installation token
5. **Job build** (`jobService.NewJobBuilder(...).Build()`) → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
6. **Queue job**: `jobService.QueueJobForExecution(ctx, job)` → **Aqueduct**, API key auth

---

### `OnPullRequestCommentCreated` (`on_pull_request_comment_created.go`)

Triggered when a PR comment mentioning Copilot is created.

**External calls:**

1. `ghFactory.NewClientForRepo(ctx, app, &event)` → installation token
2. Permission check: `gh.GetUserPermissionsForRepositoryByID(ctx, repoID, actor)` → **GitHub REST API**, installation token (checks if commenter has push access)
3. `gh.GetPullRequestContext(ctx, nodeID, number, ...)` → **GitHub GraphQL API**, installation token (fetches PR with comments, reviews, reactions)
4. Reaction management:
   - `gh.AddReaction(ctx, nodeID, content)` → **GitHub GraphQL API**, installation token
   - `gh.RemoveReaction(ctx, nodeID, content)` → **GitHub GraphQL API**, installation token
5. Comment minimization: `gh.MinimizeComment(ctx, nodeID, classifier)` → **GitHub GraphQL API**, installation token (minimizes outdated bot comments)
6. **Stacked PR flow** (if applicable):
   - `capiClient.ChatCompletions(ctx, userID, jobID, body)` → **CAPI** `POST /v1/chat/completions`, HMAC auth (for stacked PR title/intent generation)
7. **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
8. **Queue job** → **Aqueduct**, API key auth

---

### `OnPullRequestReviewSubmit` (`on_pull_request_review_submit.go`)

Triggered when a PR review mentioning Copilot is submitted.

**External calls:**

1. `ghFactory.NewClientForRepo(ctx, app, &event)` → installation token
2. `gh.GetPullRequestContext(ctx, nodeID, number, ...)` → **GitHub GraphQL API**, installation token
3. Reactions on review comments: `gh.AddReaction(...)`, `gh.RemoveReaction(...)` → **GitHub GraphQL API**, installation token
4. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
5. **Stacked PR flow** (if applicable):
   - `capiClient.ChatCompletions(...)` → **CAPI**, HMAC auth
6. **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
7. **Queue job** → **Aqueduct**, API key auth

---

### `OnPullRequestStateChanged` (`on_pull_request_state_change.go`)

Triggered when a PR is closed/merged (to finalize running jobs).

**External calls:**

1. DB reads: assignment and jobs lookup.
2. `ghFactory.NewClientForRepo(ctx, app, runningJob)` → installation token (to cancel workflows)
3. `jobExecutor.CancelJob(ctx, gh, job, owner, repo)`:
   - `gh.CancelWorkflowRunByID(...)` → **GitHub REST API**, installation token

---

### `OnWorkflowRunCompleted` (`on_workflow_run_completed.go`)

Triggered when a Copilot GitHub Actions workflow run completes.

**External calls:**

1. `ghFactory.NewClientFromRepo(ctx, app, repoID, ownerID)` → installation token
2. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
3. `gh.ListWorkflowJobs(ctx, owner, repo, runID)` → **GitHub REST API** `GET /repos/{owner}/{repo}/actions/runs/{run_id}/jobs`, installation token
4. `gh.GetPullRequestContext(ctx, nodeID, number, ...)` → **GitHub GraphQL API**, installation token
5. `gh.RequestReviewers(ctx, owner, repo, prNumber, [actorLogin])` → **GitHub REST API** (if job finalized with human-review needed), installation token
6. **Session update**:
   - `jobService.GetSessionForJob(ctx, job)` → `sessionClient.GetSession(ctx, sessionID)` → **CAPI** `GET /v1/copilot/sessions/{id}`, user/S2S token
   - `jobService.UpdateSession(ctx, job, update)` → `sessionClient.UpdateSession(...)` → **CAPI** `PUT /v1/copilot/sessions/{id}`, user/S2S token
7. **Handle pending jobs** (re-queue follow-up jobs if any):
   - `gh.GetRepositoryByID(...)`, `gh.GetPullRequestContext(...)` → **GitHub REST/GraphQL API**, installation token
   - **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
   - **Queue job** → **Aqueduct**, API key auth

---

### `OnWorkflowRunFailed` (`on_workflow_run_failed.go`)

Triggered when a CI/CD workflow run fails and Copilot is configured to auto-fix.

**External calls:**

1. `ghFactory.NewClientFromRepo(ctx, app, repoID, ownerID)` → installation token
2. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
3. `gh.GetWorkflowRunByID(ctx, owner, repo, runID)` → **GitHub REST API** `GET /repos/{owner}/{repo}/actions/runs/{run_id}`, installation token
4. `gh.ListWorkflowJobs(ctx, owner, repo, runID)` → **GitHub REST API**, installation token
5. `gh.ListCheckRunAnnotations(ctx, owner, repo, jobID)` → **GitHub REST API** `GET /repos/{owner}/{repo}/check-runs/{check_run_id}/annotations`, installation token
6. **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
7. **Queue job** → **Aqueduct**, API key auth

---

### `OnCodeScanningAlertsAssigned` (`on_code_scanning_alerts_assignment.go`)

Triggered when code scanning alerts are assigned to Copilot for fixing.

**External calls:**

1. `ghFactory.NewClientForRepo(ctx, app, &event)` → installation token
2. `gh.GetUserPermissionsForRepositoryByID(ctx, repoID, assignerLogin)` → **GitHub REST API**, installation token (checks assigner has push access)
3. `gh.GetRepositoryContext(ctx, nodeID)` → **GitHub GraphQL API**, installation token (fetches repo info)
4. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
5. **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
6. **Queue job** → **Aqueduct**, API key auth

---

### `OnMergeConflict` (`on_merge_conflict.go`)

Triggered when a merge conflict occurs on a Copilot-managed PR.

**External calls:**

1. `ghFactory.NewClientFromRepo(ctx, app, repoID, ownerID)` → installation token
2. `gh.GetRepositoryByID(ctx, repoID)` → **GitHub REST API**, installation token
3. `gh.ListPullRequestsWithCommit(ctx, owner, repo, sha)` → **GitHub REST API** `GET /repos/{owner}/{repo}/commits/{commit_sha}/pulls`, installation token (finds PR for the conflicting commit)
4. `gh.GetPullRequest(ctx, repoID, number)` → **GitHub REST API**, installation token
5. `gh.MarkPullRequestReadyForReview(ctx, prNodeID)` → **GitHub GraphQL API**, installation token (converts draft PR back to ready if needed)
6. **Job build** → see [jobservice.JobBuilder.Build](#jobservicejobbuilder-build)
7. **Queue job** → **Aqueduct**, API key auth

---

## Integration-Level-Only Calls — Are They All Twirp?

Short answer: **no**. The internal Twirp client is the primary consumer of integration-level auth, but CAPI's HMAC client is a second, entirely separate case.

### Integration-scoped callers (no per-installation token required)

| Caller | Transport | Auth |
|---|---|---|
| `githubtwirp.Client` | Twirp (HTTP/JSON over `GitHubTwirpAPIURL`) | HMAC (`GitHubTwirpHMACKey`) + `Copilot-Integration-Id` header |
| `githubtwirp.Client` → Limiter | Twirp (HTTP/JSON over `LimiterTwirpAPIURL`) | HMAC (`LimiterTwirpHMACKey`) |
| `githubtwirp.Client` → Billing | Twirp (HTTP/JSON over `BillingClientURL`) | HMAC (`BillingClientHMACKey`) |
| `capi.HmacClient` | REST JSON over `CAPIBaseURL` | HMAC (`CAPIHMACKey`) + `Copilot-Integration-Id` header |

The Twirp calls that are integration-level only (no user or installation token) include:

- `SweagentdAPI().ConfigurationForRepository` — checks Copilot enablement for a repo
- `SweagentdAPI().GetRepositoryInstallation` — resolves the GitHub App installation for a repo
- `SweagentdAPI().MintServerToServerTokenForRepo` — mints an installation-scoped S2S token (the output of this call _is_ the installation token used by everything else)
- `SweagentdAPI().GetUserToServerToken` — mints a user-to-server token on behalf of a user
- `LimiterAPI().GetQuotaRemaining` — checks Copilot premium quota
- `UserDetailAPI().GetCopilotUserDetails` — returns subscription plan and feature flags
- `AuthorizationAPI().BatchControlAccess` — checks token permissions against resource-action pairs
- `RepositoriesAPI().FindRepositories` / `FindRepositoriesByName` — resolves repo metadata
- `capi.HmacClient.ListCodingAgentModels` — returns available Copilot coding-agent models
- `capi.HmacClient.CreateModelSession` — creates an AI model session (agentic jobs)
- `capi.HmacClient.ChatCompletions` — generates stacked PR titles/intent summaries

### Installation-scoped callers (require an installation token)

Everything that calls the GitHub REST or GraphQL API does so with an **installation token** (minted via `MintServerToServerTokenForRepo` above) or a **user/OAuth token** (forwarded from the original request). There is no case where a raw integration credential is forwarded to the public GitHub API.

Content-generating GitHub REST/GraphQL operations are subject to GitHub secondary rate limits in addition to primary rate limits. For installation-scoped writes, this can become a **per-installation hard wall**: a single hot installation can exhaust content-creation headroom even when global REST/GraphQL request volume looks low.

Note: `HandleCheckEnablement` is a user-token-only path — it constructs its GitHub client via `NewClientForUser` (forwarding the caller's OAuth token) and does not mint an installation token.

### Key distinction: CAPI is not Twirp

Although both `githubtwirp.Client` and `capi.HmacClient` use HMAC + `Copilot-Integration-Id`, they are completely separate HTTP clients calling different backends:

- **Twirp client** → GitHub internal monolith / related internal services (`GitHubTwirpAPIURL`, `LimiterTwirpAPIURL`, `BillingClientURL`)
- **CAPI HMAC client** → GitHub Copilot API (`CAPIBaseURL`, e.g. `https://api.githubcopilot.com`)

CAPI also has a second, user-scoped mode (`capi.UserClient` / `sessionClient`) that uses forwarded user tokens or freshly minted S2S tokens for session lifecycle calls (`CreateSession`, `GetSession`, `UpdateSession`). That path is **not** integration-level.

---

## Summary Table: Credential Usage by Service

| External Service | Authentication Method | Who Uses It |
|---|---|---|
| **GitHub REST API** (public / internal) | Installation token (S2S, minted via `SweagentdAPI`)  | `NewClientFromRepo`, `NewClientForRepo`, `NewClientFromRepoName` — used by jobexecutor, event handlers, callback, jobservice builder |
| **GitHub REST API** | User/OAuth token (forwarded from request) | `NewClientForUser` — used by jobapi middleware for permission checks, cancel job |
| **GitHub GraphQL API** | Same token as the REST client (installation or user token) | `GetPullRequestContext`, `GetRepositoryContext`, `GetIssueContext`, `AddReaction`, `MinimizeComment`, etc. |
| **GitHub Twirp API** (`UserDetailAPI`, `SweagentdAPI`, `AuthorizationAPI`, `RepositoriesAPI`) | HMAC (`GitHubTwirpHMACKey`) | `githubtwirp.Client` — used widely across all handlers for enablement, user details, token minting, PR creation, authorization |
| **Limiter Twirp API** (`CopilotLimiterAPI`) | HMAC (`LimiterTwirpHMACKey`) | `CheckPremiumQuota` — called from quota check paths in all create-job endpoints |
| **CAPI** (session management) | User token (forwarded OAuth/installation token, minted per-job) | `sessionClient.CreateSession`, `GetSession`, `UpdateSession` — called from jobservice session management |
| **CAPI** (model/completions) | HMAC (`CAPIHMACKey`) | `ListCodingAgentModels` (model resolution), `CreateModelSession` (agenthttp getJob), `ChatCompletions` (stacked PR generation) |
| **Aqueduct** (job queue) | API key (`AqueductAPIKey` / staging variants) | `QueueJobForExecution`, `QueueJobForProcessing`, `RequeueJobWithDelay` |
| **ExP (Experimentation)** | None (no auth header) | `experiments.GetFeatureAssignment` — called from job creation pipeline |
| **Spokes** (internal git service) | Internal S2S (no user token) | `CreateEmptyCommit`, `CreateBranch` — called from jobservice builder |
| **GitHub Apps REST API** (for token minting in `agenticapp`) | App JWT (private key) | `Apps.FindRepositoryInstallationByID`, `Apps.CreateInstallationToken`, `POST /app/global/access_tokens` |
| **Billing Platform** | HMAC (`BillingClientHMACKey`) | Available via `BillingClient()` on the Twirp client — not directly called from handlers in the reviewed code |

---

## Datadog Metric Source Links (2-week window)

- **All endpoint RPS source (`sweagentd.response_count` by `http.path`)**: https://app.datadoghq.com/metric/explorer?start=1774965600000&end=1776168000000&paused=true#N4Ig7glgJg5gpgFxALlFOAzCA7CCID22KoATnAI4CucAzgrSgNpoS0AOANgIYCeA+gl7s4KEJxyiANCAwFSAWyo9GyFrPlKeY6nFK8ADCAC+AXRm7SEOszTcE3frQJVSAY1HIQCxFbeMZbG4fHRp9Iwsw3jFaKgVkWjA4bnhsBCgAOnIOIlo4fjcXNOA4bAA3ZHZSAigqN3wiYwACACNeJuAACwQEdgz2e07jE3MQbPZc-LlFezF8HzyrGxl6Xk5PUAlsfKERGIIJKBAZLfzIKAROsWxNbk5jkAH1ns8QKAIYApVaCDcTMxku1e8zoemsjGMJz4LiQqBAnTgEBg3RQAEYZOdLmiZAAPbEgaLIVHGSEgDgSBAAYSIWBgKGwyk4xiAA
- **Job throughput sources (`sweagentd.hydro.event_received`, `sweagentd.jobs.created`, `sweagentd.jobs.completion`, `sweagentd.triggers.job_queued`)**: https://app.datadoghq.com/metric/explorer?start=1774965600000&end=1776168000000&paused=true#N4Ig7glgJg5gpgFxALlFOAzCA7CCID22KoATnAI4CucAzgrSgNpoS0AOANgIYCeA+gl7s4KEJxyiANCAwFSAWyo9GyFrPlKeY6nFK8ADCAC+U0HMXLuOmvoCMJsxsvbkIXfoBMj85qs29XgBmEwBdGQ8IOmY0bgRufloCKlIAY1E3BURSCFTGGWxuLID9IwjbXjFaKgVkWjA4bnhsBCgAOgALXihSAja4ADc4Fv5ydIghqGBhgeR2XqgqVPwiYx8QKDiEpJT0sSyEHLyQAqKM9wqHcsCqmrqGpuHWtoArAgAjWjbU8ji4KZmcwWSxW2DWpli8USyTS5wOR3yIEKxTcHl43mu+hutXqjWazzen2+BAUXEQhGw02ws3mBEWywp4KcmyhO1h+2yuURyPOaJCmMqbmqOIe+PahwgMHgpC+hP4uhoAOpQLpIMZYRk5A4RFocH4FgUcTE+Cyupy0Rk9F4nAyoAk2D1QhEVQIEigJ3Ekn4kCgCA6Ymwmm4nA97GDiAQ5ygBBg-FSKlouRMxnCICd5xNdD0UUYpnEfGSSFQIA6cElHSLdhkPr9KCrIAAHnWZIK7MY8xwJAgAMJELAwFDYZScYxAA
