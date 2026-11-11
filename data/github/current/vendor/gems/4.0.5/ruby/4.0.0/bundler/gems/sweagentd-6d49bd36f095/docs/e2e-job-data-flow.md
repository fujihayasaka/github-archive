# E2E Job Data Flow Analysis

> **Related:** [API Dependency Map](./api-dependency-map.md) | [Job Lifecycle Timing](./job-lifecycle-timing.md) | [E2E Architecture Diagram](./e2e-flow.excalidraw) | [Discussion #10894 — Scaling & capacity context](https://github.com/github/sweagentd/discussions/10894)
> **Issue:** [#11571 — Understand the data flow of a full e2e job](https://github.com/github/sweagentd/issues/11571)
> **Data window:** 7-day (2026-04-14 → 2026-04-21)

---

## Executive Summary

An **average sweagentd job generates an estimated ~9,250 downstream calls**[^total] across its lifecycle (including ~5,095 Redis ops[^redis], ~2,557 CosmosDB ops[^cosmos], ~1,115 Twirp wire calls[^twirp], and ~442 CAPI calls). The overwhelmingly dominant phase is the **agent callback/execution loop** (~1,094 callbacks per job[^callbacks]), which generates ~9,132 of those calls — **~99% of all downstream traffic**. Job creation and completion account for ~113 calls combined[^creation].

> **Why ~1,094 callbacks for a session with ~29 LLM turns?** The agent runtime streams `kind:progress` events to sweagentd — not one per LLM turn, but one per streaming chunk, message, tool result, and model call event. 99.5% of callbacks are `kind:progress`[^progress], sent roughly every ~0.5 seconds during the 9.3-minute execution phase. The remaining ~6 are result/error/comment callbacks.

**Callback auth is entirely Twirp/HMAC — no REST.**[^auth] GitHub REST calls only fire from result handlers (~0.7% of callbacks)[^result] when the agent updates PRs or comments. Token minting is a Twirp call with aggressive 55-minute caching[^tokencache].

**The single biggest scaling lever is likely the callback frequency.** At the 7-day baseline throughput (~2,100 jobs/hour)[^throughput], sweagentd generates ~640 callbacks/sec. Twirp rate limits appear to have **~10× headroom** based on the monolith's server-side limiter (8-10% utilization on hottest path). CosmosDB and Redis limits are unknown — these are the primary unknowns for scaling[^twirplimit].

> ⚠️ **Recent live load is higher than the 7-day baseline.** A later spot-check saw ~944 callback RPS over 1 hour and ~985 callback RPS over 4 hours, with ~1.45K-1.49K callbacks/job. Treat the 7-day `1,094 callbacks/job` and `~640 callbacks/sec` values as a baseline for this analysis, not a ceiling; current load can run ~30-50% higher.

**Observability update:** cache-backed Twirp helpers now emit explicit `.fetch` subspans only when they go over the wire. Wrapper spans such as `githubtwirp.Client.GetCopilotUserDetails` should be read as invocation/cache-path signal; a cache hit has no `.fetch` subspan, while a miss has `githubtwirp.Client.GetCopilotUserDetails.fetch` around the RPC. The `sweagentd.github.api.*` metrics also now carry `api_target` and `auth_type` tags, which give full-sample aggregate API volume by surface and credential.

[^total]: Sum of all rows in the [Grand Total Per Job](#grand-total-per-job) table. Per-job counts derived from full-sample metrics where available, fetch subspans / HTTP spans for over-the-wire calls, and wrapper-span ratios to callbacks where sampled APM is still needed to isolate job-lifecycle traffic. **These are estimates, not exact counts** — see [methodology](#data-sources-and-methodology) for confidence levels.
[^redis]: [`sweagentd.cache_operation`](https://app.datadoghq.com/metric/explorer) metric (1-day sum: 257M) ÷ daily jobs (50,512). Confirmed as Redis via `internal/cache/rediscachestore.go`.
[^cosmos]: APM span counts for `cosmosdb.*` / `read_item` / `query_items` / `upsert_item` resource names (1-day), adjusted for ~1.5% sampling rate, ÷ daily jobs. Creation phase (27 ops) verified from [APM trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309).
[^twirp]: ~1,115 wire calls/job = AuthorizationAPI ~711 (uncached, 0.65/callback) + SweagentdAPI ~355 (IsAgentEnabled uncached at 0.32/callback + ~5 creation) + GetRepoByName ~45 (uncached, 0.04/callback) + UserDetailAPI ~4 (heavily cached, 5-min TTL). Note: wrapper spans overcount wire calls because `IsMemoryEnabled` (~66 invocations/job) and `GetCopilotUserDetails` (~3,263 invocations/job) fire method-level spans even when they read context/Redis cache. Use fetch subspans (for cache-backed helpers) or HTTP spans (for uncached RPCs) to count actual Twirp requests. See [Twirp sub-API detail](#twirp-sub-api-detail) and [#11692](https://github.com/github/sweagentd/issues/11692).
[^callbacks]: `sum(sweagentd.agentcallback.requests)` 7-day = [386,849,785](https://app.datadoghq.com/metric/explorer?start=1776195084224&end=1776799884224) ÷ `sum(sweagentd.jobs.created)` 7-day = 353,584 → **1,094 callbacks/job**.
[^progress]: `sweagentd.agentcallback.requests` by `kind` tag (1-hour sample): `kind:progress` = 2,094,177 (99.5%), `kind:partialresult` = 6,494, `kind:result` = 3,438, `kind:commentreply` = 1,187, `kind:error` = 191. Progress callbacks are streaming events (per-chunk, per-message, per-tool-result), not 1-per-LLM-turn.
[^creation]: Creation+processing: ~101 total calls, including ~61 non-Redis downstream wire calls and ~40 Redis ops (verified from [APM trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309) — 14 Twirp wrapper spans / 5 non-Limiter Twirp wire calls, 2 Limiter Twirp calls, 9 REST, 27 CosmosDB, 11 Spokes, 3 CAPI, 2 ExP, 2 Aqueduct, 35 Vexi in-process checks). Completion: ~12 calls (from code analysis of `OnWorkflowRunCompleted` in [API dependency map](./api-dependency-map.md)).
[^auth]: Code analysis of `internal/agentcallback/handler.go` and `internal/auth/auth.go` — auth chain is `authndClient.AuthenticateAPIToken()` → `ghTwirp.GetCopilotUserDetails()` → `ghTwirp.IsAgentEnabled()` → `ghTwirp.TokenHasAccess()`. All Twirp HMAC, zero REST.
[^result]: APM 1-hour: 266 result-handler REST spans (`UpdatePullRequest`, `CreateComment`, `RequestReviewers`, etc.) vs 36,848 `agentcallback.HandleCallback` spans → 0.7%. See `internal/agentcallback/handle_result.go`.
[^tokencache]: `internal/github/tokens/tokens.go:17` — `tokenCacheTTL = 55 * time.Minute`. Key: `target:{app}:repo_id:{repo}`. Minting via `SweagentdAPI().MintServerToServerTokenForRepo` (Twirp HMAC, not REST).
[^throughput]: `sum(sweagentd.jobs.created)` 7-day = [353,584](https://app.datadoghq.com/metric/explorer?start=1774965600000&end=1776168000000) ÷ 168 hours = 2,105 jobs/hour. Average job duration: `avg(sweagentd.jobs.total_duration_ms)` 7-day = 1,137,496ms ≈ 19 min. Concurrent jobs: 0.585 jobs/sec × 1,140s = ~665.
[^twirplimit]: `github/github app/api/limiters/internal/twirp_request_count_by_client_and_path.rb:18` — default 100,000/min. sweagentd has a custom override only for `RepositoriesAPI/FindRepositoriesByName` (400,000/min).

---

### How much room do we have?

> **At 2× current load, the HTTP pods' CPU is the binding constraint.** The `sweagentd` HTTP deployment (which handles all ~1,094 callbacks/job) peaks at **39% CPU** with only **~2.6× headroom** to its 2-core limit. At 2× jobs, these pods would be near CPU saturation. This is tighter than any downstream rate limit.

| Constraint | Current | Limit | Headroom | At 2× | Source |
|---|---:|---|---:|---|---|
| **`sweagentd` HTTP pod CPU** | **0.78c peak** | **2c** | **~2.6×** | ⚠️ ~78% | [Dashboard (Saturation)](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) |
| `sweagentd` HTTP pod memory | 138 MB peak | 524 MB | ~3.8× | ~53% | Same dashboard |
| Twirp request count (per path) | ~8-10% | 100K/min | ~10× | ~20% | [Monitor 275922103](https://app.datadoghq.com/monitors/275922103) |
| Twirp concurrency (shared) | ~12% peak | 600 concurrent | ~8× | ~24% | Same monitor |
| Aqueduct agent-pool | 2.6% peak | 100% | ~38× | ~5% | [Dashboard (Aqueduct)](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) |
| GitHub content creation secondary limit | Unknown by installation | ~80 content-generating requests/min, ~500/hour (some endpoints lower) | **Unknown / hard wall for hot installations** | Unknown | [GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#about-secondary-rate-limits) |
| CosmosDB | ~1,494 RPS | Unknown | **Unknown** | ~2,988 RPS | — |
| Redis | ~2,973 RPS | Unknown | **Unknown** | ~5,945 RPS | — |

> ⚠️ **2× with CCR may need more HTTP pods.** The 2× CPU estimate assumes linear scaling (2× jobs ≈ 2× CPU), which is a simplification. The actual relationship depends on whether callback processing has shared efficiencies (connection pools, caching) or contention costs (GC pressure, lock contention). Since each callback is a mostly-independent HTTP request (DB reads + Twirp calls), linear is a reasonable approximation — but load testing would be needed to confirm. HPA can add more HTTP pods, so this isn't a hard wall, but it needs to be planned for. CosmosDB and Redis provisioned capacity are the other unknowns.

> **Twirp rate limit: ~8-10% utilization today on the hottest path.** The monolith's server-side limiter metric [`api.limiter.gauge.percent{key:sweagentd}`](https://app.datadoghq.com/monitors/275922103) is **the ground truth** — it's the actual limiter reporting its own state, not an estimate.

> ⚠️ **Per-job ratios are NOT perfectly stable.** 7-day analysis of `downstream_metric / jobs.created` shows 20-37% coefficient of variation (CV%) across 8-hour bins:
>
> | Metric | Avg/Job | Min | Max | Spread (CV%) | Verdict |
> |---|---:|---:|---:|---:|---|
> | Callbacks/job | 1,203 | 917 | 2,006 | ±21% | Somewhat variable |
> | Redis/job | 4,685 | 3,642 | 8,347 | ±22% | Somewhat variable |
> | github-twirp/job | 1,699 | 1,154 | 3,963 | ±37% | Unstable — 2-3× swings |
> | auth-twirp/job | 488 | 359 | 1,098 | ±34% | Unstable — 2-3× swings |
> | CAPI/job | 523 | 360 | 1,162 | ±36% | Unstable — 2-3× swings |
>
> _(Spread = coefficient of variation: std dev ÷ mean. ±20% means the ratio typically swings 20% above/below the average.)_
>
> The Twirp and CAPI ratios vary ~2-3× between bins. This likely reflects **non-job traffic** (HandleCheckEnablement, event processing) that doesn't scale proportionally with jobs. Callbacks/job (which IS job-only) is more stable at ~20% CV. **Our linear scaling estimates are directionally correct but could be off by 2× in either direction for Twirp paths.** The [graph formulas below](#datadog-graph-formulas-rps-per-job-over-time) let you track this over time.

[^limiter_code]: Verified from `github/github app/api/limiters/internal/twirp_request_count_by_client_and_path.rb` — key is `client_name:SHA256(path)`, window 60s, default 100K/min. sweagentd has custom override only for `RepositoriesAPI/FindRepositoriesByName` (400K/min). Each RPC method gets its own 100K bucket.

> **Why our client-side metrics were misleading:** The sweagentd metric `sweagentd.github.api.request{client_name:github-auth-twirp}` shows ~59K/min. We initially assumed this was a single Twirp path and calculated 59K ÷ 100K limit = 59% utilization = only 1.7× headroom. But `github-auth-twirp` is a **client_name tag**, not a path — it aggregates ALL RPC methods routed through the auth Twirp client (e.g., `BatchControlAccess`, `EvaluatePolicies`, etc.). The per-path limiter keys by `client:SHA256(path)`[^limiter_code], so each RPC method gets its own 100K/min bucket. The 59K/min is spread across multiple buckets, and the **server-side monitor confirms the hottest single bucket is only at ~8-10%** (~8-10K requests/min).

Three Twirp limiters run on the monolith for every sweagentd request. They operate independently — hitting ANY one of them triggers rate limiting:

| Limiter | What it limits | Limit | Key | Current | Headroom | Source |
|---|---|---|---|---:|---:|---|
| **Request count** | Requests/min per RPC method | 100K/min | `client:SHA256(path)` — each RPC gets its own bucket | **~8-10%** | **~10×** | [Monitor](https://app.datadoghq.com/monitors/275922103) |
| **Concurrency** | In-flight requests across ALL methods | **600 concurrent** | `client` only — **path-agnostic, one shared bucket** | **~12% peak** | **~8× at peak** | Same monitor |
| Elapsed time | Total processing time | — | — | ~0.2% | ~500× | Same monitor |

> ⚠️ **The concurrency limiter is likely the tighter constraint.** Unlike request count (which has a separate 100K/min bucket per RPC method), the concurrency limiter is **path-agnostic** — ALL sweagentd Twirp calls share a single pool of 600 in-flight slots[^concurrency_limiter]. At ~12% peak utilization (~73 concurrent), we have **~8× headroom** before peak spikes hit the limit. Slow Twirp calls (e.g., `MintServerToServerTokenForRepo` at ~100ms) consume more concurrency slots than fast ones because they hold a slot for longer.

[^concurrency_limiter]: `github/github app/api/limiters/internal/twirp_concurrent_by_client.rb` — key is `client_name` only (no path), limit 600 concurrent in-flight requests, no custom overrides for sweagentd. Tracks increment on request start, decrement on finish.

**Per-dependency marginal cost** (each additional concurrent job adds):

| Dependency | +RPS/job | Wire Calls/Job | Known Limit | Headroom |
|---|---:|---:|---|---|
| Redis (in-cluster) | +4.47 | ~5,095 | Unknown (Azure tier) | ? |
| CosmosDB | +2.24 | ~2,557 | Unknown (provisioned RU/s) | ? |
| Twirp → all paths (per-path limit) | +0.97 | ~1,115 | 100K/min each path | **~10×** (from server-side monitor) |
| CAPI HMAC | +0.39 | ~442 | Unknown | ? |
| GitHub REST API | +0.02 | ~19 | Per-install secondary | High |
| Spokes | +0.01 | ~11 | Internal S2S | High |

> ⚠️ **Estimation caveat:** CosmosDB, TokenHasAccess, and IsAgentEnabled per-job counts are derived from **~1.5% sampled APM span ratios** (ratios are useful for callback attribution even though absolute counts are sampled — see [methodology](#data-sources-and-methodology)). Twirp wire counts should be checked against fetch subspans or HTTP child spans, because cached wrapper spans do not imply network calls. Redis and callback counts come from **full-sample metrics** (high confidence). Creation-phase counts come from **a single APM trace** (n=1). The `api_target` / `auth_type` tags from [PR #11428](https://github.com/github/sweagentd/pull/11428) now provide full-fidelity aggregate API volume by surface, but they do not by themselves separate job-lifecycle traffic from non-job traffic.
>
> ⚠️ **Non-job traffic:** sweagentd also handles traffic that doesn't create jobs — `HandleCheckEnablement` (UI checks), event processing that filters out, `/models` endpoint, etc. This traffic contributes to Twirp and REST metrics but **may not scale linearly with job count**. If non-job traffic is proportional to GitHub.com page views (not agent jobs), then the marginal cost per job overestimates the Twirp impact and the ~10× Twirp headroom is even better than it looks. Conversely, if enablement checks scale with adoption (more repos enabled → more UI checks), it could eat into headroom independently. **Follow-up: detangle job-lifecycle vs non-job traffic** — `api_target` / `auth_type` tags now separate API surface and credential, but we still need route/job-phase attribution or a correlation with `HandleCheckEnablement` volume to fully isolate non-job traffic.

### Compute resource headroom

sweagentd runs as four separate deployments. Source: [sweagentd dashboard](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) (Saturation section).

| Deployment | Role | CPU peak | CPU limit | CPU headroom | Mem peak | Mem limit | Mem headroom |
|---|---|---:|---:|---:|---:|---:|---:|
| **`sweagentd`** | HTTP server (callbacks, agenthttp, jobapi) | 0.78c | 2c | **~2.6×** | 138 MB | 524 MB | ~3.8× |
| `sweagentd-worker` | Aqueduct worker (event/api/agent jobs) | 0.24c | 2c | ~8.2× | 94 MB | 524 MB | ~5.6× |
| `sweagentd-twirp` | Twirp RPC server (CreateJob, CancelJob) | 0.08c | 2c | ~24× | 154 MB | 524 MB | ~3.4× |
| `sweagentd-scheduler` | Interval trigger scheduler | 0.08c | 2c | ~26× | 84 MB | 524 MB | ~6.3× |

**Aqueduct worker pool utilization:**

| Pool | Avg | Peak | Headroom |
|---|---:|---:|---:|
| event-pool | 0.7% | 1.3% | ~76× |
| agent-pool | 1.3% | 2.6% | ~38× |
| api-pool | <0.1% | 0.2% | ~2,000× |

> **The `sweagentd` HTTP deployment is the tightest** at ~2.6× CPU headroom on the hottest pod during peak. This is the pod that handles the ~1,094 callbacks/job — the dominant traffic. The Twirp and worker deployments have plenty of room. Note: all deployments can scale horizontally via HPA (more pods), so the per-pod ceiling isn't a hard wall — it just means we'd need more HTTP pods first.

---

### Data sources and methodology

All per-job numbers are **averages** (total ÷ job count), not medians. The distribution is right-skewed (some very long jobs), so the average overestimates the typical job. The data window is 7 days (2026-04-14 → 2026-04-21) unless noted otherwise.

| Number | Source | Sampling | Cross-validation |
|---|---|---|---|
| Callbacks/job (1,094) | `agentcallback.requests` ÷ `jobs.created` (7-day) | **Full sample** | ✅ Today's 1-day = 1,282/job (varies by day) |
| Redis/job (~5,095) | `cache_operation` ÷ daily jobs | **Full sample** | ✅ Today's 1-day = 4,246/job (varies by day) |
| Jobs/hour (2,105) | `jobs.created` (7-day) | **Full sample** | ✅ |
| Job duration (19 min) | `jobs.total_duration_ms` (7-day avg) | **Full sample** | ⚠️ This is the **average**, not the median (p50). Skewed by long-tail jobs. |
| Creation phase (~61 non-Redis calls, ~101 incl. Redis) | Single APM trace [3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309) | **n=1 trace** | ⚠️ Representative but may vary per job type |
| CosmosDB/job (~2,557) | APM span ratios to callbacks (1-day) | **~1.5% sampled** | ❌ No full-sample CosmosDB count metric exists |
| TokenHasAccess/job (~711) | APM wrapper-span ratio to callbacks (0.65/cb × 1,094), checked against outbound HTTP spans by `rpc.method:BatchControlAccess` | **~1.5% sampled for per-job attribution; full sample for aggregate metric volume** | Partial: `api_target` / `auth_type` metrics validate aggregate HMAC/internal Twirp volume when tagged; HTTP spans grouped by `rpc.method:BatchControlAccess` are the direct wire-call check and include non-job traffic |
| REST/job (~19) | APM span ratios | **~1.5% sampled for per-job attribution; full sample for aggregate metric volume** | Partial: `sweagentd.github.api.request{api_target:public_rest}` + `{api_target:internal_rest}` split by `auth_type`, but includes HandleCheckEnablement etc. |
| Twirp sub-API breakdown | APM wrapper-span ratios + cache-backed `.fetch` subspans + HTTP child spans + code analysis | **Mixed** | `sweagentd.github.api.request{api_target:internal_twirp_*}` validates aggregate wire volume; `.fetch` subspans distinguish cache hits from real RPCs for cache-backed helpers |

> **Why APM ratios are useful for per-job numbers:** Every callback is tied to a running job, so the ratio "downstream spans ÷ callback spans" gives a reliable per-callback rate when the same sampled trace population contains both spans. We then multiply by callbacks/job (1,094, from full-sample metrics) to get per-job counts. For cached helpers, use wrapper spans for invocation rates and `.fetch` subspans for wire-call rates; a cache hit has no `.fetch` subspan.
>
> **Why full-sample metrics still can't replace APM for per-job attribution:** Metrics like `sweagentd.github.api.request` now have `api_target` / `auth_type` tags, which is enough for API surface and credential breakdowns. They still include non-job traffic (HandleCheckEnablement ~8K/hr, event processing that doesn't create jobs, /models endpoint). Dividing by `jobs.created` can inflate per-job numbers. APM ratio-to-callbacks avoids this because callbacks are exclusively job-lifecycle.
>
> **Now available: [PR #11428](https://github.com/github/sweagentd/pull/11428)** adds `api_target` and `auth_type` tags to `sweagentd.github.api.request`, `sweagentd.github.api.error`, `sweagentd.github.api.rate_limit_remaining`, and `sweagentd.github.api.rate_limit_exceeded`. Use these tags for full-sample aggregate views, and use APM/fetch spans for job-lifecycle attribution and cache-hit vs wire-call analysis.

---

## Trigger Type Variance

> **Finding: Trigger types do NOT meaningfully differ in their downstream call profile.**

| Queue | 7-day Volume | % of Total | Notes |
|---|---:|---:|---|
| `event-job-queue` (Hydro events) | 262,449 | 74% | PR comments, issue assignments |
| `N/A` (Direct Twirp from GitHub.com) | 73,547 | 21% | UI-initiated |
| `api-job-queue` (Async HTTP API) | 17,244 | 5% | HandleNewJobAsync |
| `event-job-trigger-queue` (Interval) | 261 | <0.1% | Scheduled triggers |

**Why they're similar:** All trigger paths converge to the same `jobservice.CreateJobForAssignment` → `JobBuilder.Build()` pipeline. The only variance is 1-3 extra REST calls in event handlers for fetching issue/PR context. The callback loop (which dominates) is identical regardless of trigger source.

---

## Phase 1+2: Job Creation & Processing (trigger → agent launched)

**~61 non-Redis downstream wire calls per job** (verified from [APM trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309); excludes ~40 Redis ops and 35 in-process Vexi feature flag checks)

The trace below is a real production job showing every span in the creation+processing path:

| Downstream | Traced Wrapper Spans | Wire Calls | Key Operations |
|---|---:|---:|---|
| **CosmosDB** | **27** | **27** | 10 query_items, 3 upsert_item, 2 read_item assignments, job reads/writes |
| **GitHub Twirp (HMAC, excluding LimiterAPI)** | **14** | **5** | wrapper spans for 9 GetCopilotUserDetails, 2 IsAgentEnabled, 2 GetCustomerID, 1 GetRepoById; only 5 non-Limiter child RPCs were observed after cache hits |
| **Limiter Twirp (HMAC)** | **2** | **2** | quota/customer checks (`GetQuotaRemaining`, `GetConsumptiveUser`) |
| **Spokes** | **11** | **11** | 3 CheckForExistingRef, 3 CheckForExistingBranch, 2 ReadBlobByObjectIDPath, 2 ReadBlob, 1 GetObjectID |
| **GitHub REST API** | **9** | **9** | 2 GetRepositoryByID, 1 GetUserByID, 1 ListBranchProtectionRules, 1 ListRepositoryRulesForBranch, 1 GetRepositoryPermissionLevel, 1 GetUserPermissionsForRepositoryByID, 1 CreateDynamicWorkflowRun, 1 GetCopilotEnvironmentSecretsAndVariables |
| **CAPI (HMAC)** | **3** | **3** | 1 ChatCompletions, 1 listModels, 1 ListCodingAgentModels |
| **ExP** | **2** | **2** | 1 getExperiments, 1 SetExperimentAssignments |
| **Aqueduct** | **2** | **2** | 1 QueueJobForExecution, 1 agentjob.Handler |
| **Feature flags** | **35** | **0** | Vexi.IsEnabledWithDefaultValue (in-process, no network) |

> ⚠️ Of the 14 Twirp wrapper spans, only **5 are wire calls**. The 9 `GetCopilotUserDetails` wrapper spans include 8 cache hits (1 has a `.fetch` subspan that populates the cache; subsequent calls hit context memo or Redis). See [UserDetailAPI wrapper spans vs wire calls](#userdetailapi-wrapper-spans-vs-wire-calls) for details.

---

## Phase 3: Agent Callback Loop ⚡ THE DOMINANT PHASE

**~1,094 callbacks per average job → ~9,132 execution-phase downstream calls per job** (including ~5,050 Redis ops, ~3,644 callback-handler non-Redis calls, and ~438 CAPI HMAC calls from execution-time model traffic)

During agent execution, the runtime agent (running in GitHub Actions) repeatedly calls back to sweagentd via CAPI to report progress, fetch commands, and update state.

### Auth on Each Callback — No REST, All Twirp

> **Each callback does NOT make GitHub REST API calls during auth.** Auth is purely Twirp + HMAC.

Per-callback auth flow (from code analysis of `internal/agentcallback/handler.go` + `internal/auth/auth.go`):

1. **Token validation:** `authndClient.AuthenticateAPIToken()` → Twirp HMAC call to authnd (not REST)
2. **User details:** `ghTwirp.GetCopilotUserDetails(userID)` → Twirp HMAC, **cached 5 minutes**
3. **Agent enablement:** `ghTwirp.IsAgentEnabled()` → Twirp HMAC (feature-flagged bypass available)
4. **Token access check:** `ghTwirp.TokenHasAccess()` → Twirp HMAC (~59% of callbacks)

**Token acquisition** (when a result handler needs a GitHub client): `MintServerToServerTokenForRepo` is a Twirp HMAC call, **not REST**. Tokens are **cached 55 minutes** (key: `target:{app}:repo_id:{repo}`) so minting only fires on first callback per repo window.

### REST Calls Happen Only in Result Handlers

Most callbacks are "progress" type (zero REST). REST calls fire only in **result handlers** when the agent wants to update GitHub resources:

| Callback Kind | REST API Calls | Example Operations |
|---|---:|---|
| **progress** (majority) | 0 | Telemetry + DB write only |
| **task_result** | 0 | DB store only |
| **error** | 0 | DB store only |
| **fix_result** | 1-2 | `GetRepositoryByID`, `UpdatePullRequest` |
| **fix_pr_comment_result** | 2-5 | `GetRepository`, `GetComment`, `UpdateComment`, `CreateComment`, `UpdatePullRequest` |
| **check_quota** | 0 | DB query only |

From APM: ~266 result-handler REST calls vs ~36,848 callbacks/hour → **~0.7% of callbacks trigger REST calls**. Per job: ~8 REST calls from callback result handlers.

### Per-Callback Operations (all types)

| Downstream | Operation | Ratio per Callback | Per Job (~1,094 callbacks) |
|---|---|---:|---:|
| CosmosDB | `GetJob` | 1.21 | ~1,324 |
| GitHub Twirp | `TokenHasAccess` | 0.65 | ~711 |
| GitHub Twirp | `IsAgentEnabled` / `ConfigurationForRepository` | 0.32 | ~350 |
| GitHub Twirp | `GetRepoByName` | 0.04 | ~44 |
| GitHub Twirp | `GetCopilotUserDetails.fetch` | 0.003 | ~3 |
| CosmosDB | `GetCommandsWithStatus` | 0.45 | ~492 |
| CosmosDB | `BatchPatchCommands` | 0.45 | ~492 |
| CosmosDB | `CreateProgress` | 0.20 | ~219 |
| GitHub REST | Result handler ops | 0.007 | ~8 |
| **TOTAL** | | | **~3,644** |

**Methodology:**
- **Callbacks per job:** `sum(sweagentd.agentcallback.requests) / sum(sweagentd.jobs.created)` over 7 days = 386,849,785 / 353,584 = **1,094**
- **Per-callback ratios:** APM span proportions (1-day window). Use wrapper spans for invocation ratios, `.fetch` subspans for cache-backed helper wire misses, and HTTP child spans for uncached RPC wire-call ratios.

---

## Phase 4: Completion (workflow done → finalized)

~7 calls per job.

| Downstream | Operation | Count |
|---|---|---:|
| GitHub Twirp | `MintServerToServerTokenForRepo` | 1 |
| GitHub REST | `GET /repos/.../actions/runs/{id}` | 1 |
| CAPI | `UpdateSession` (final status) | 1 |
| GitHub REST | PR comment/update (if applicable) | 0-2 |
| Hydro | `PublishJobCompleted` event | 1 |
| CosmosDB | Job status updates | ~3 |

---

## Grand Total Per Job

| Downstream System | Auth | Creation+Processing | Callback Loop | Completion | **Wire Calls/Job** |
|---|---|---:|---:|---:|---:|
| **Redis** | Internal | ~40 | ~5,050 | ~5 | **~5,095** |
| **CosmosDB** | Internal | 27 | ~2,527 | ~3 | **~2,557** |
| **GitHub Twirp (wire only)** | HMAC | ~5 | ~1,109 | ~1 | **~1,115** |
| **Spokes** | S2S | 11 | — | — | **~11** |
| **GitHub REST API** | Install token | 9 | ~8 | ~2 | **~19** |
| **CAPI (HMAC + User/S2S)** | Mixed | 3 | ~438 | ~1 | **~442** |
| **Limiter Twirp** | HMAC | ~2 | — | — | **~2** |
| **ExP** | None | 2 | — | — | **~2** |
| **Aqueduct** | API key | 2 | — | — | **~2** |
| **TOTAL** | | **~101** | **~9,132** | **~12** | **~9,245** |

*Note: "GitHub Twirp (wire only)" excludes cached `GetCopilotUserDetails` wrapper spans and `IsMemoryEnabled` wrapper spans that read already-cached UserDetails. Use cache-backed `.fetch` subspans and lower-level HTTP spans grouped by `rpc.method` to count actual over-the-wire Twirp calls. See [Twirp sub-API detail](#twirp-sub-api-detail).*

*Creation+Processing column verified against [APM trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309).*

---

## Marginal Cost Per Job

> **Key question:** If I add one more concurrent average job, how much RPS does each downstream system see?

Average job duration: 19 min (1,140s). Execution phase: 9.3 min (558s). Formula: `Marginal RPS = Total Calls/Job ÷ Job Duration (s)`

| Downstream (wire calls only) | Startup | Execution | Wrap-up | Total/Job | **+RPS/job** |
|---|---:|---:|---:|---:|---:|
| **Redis** | ~40 | ~5,050 | ~5 | ~5,095 | **+4.47** |
| **CosmosDB** | 27 | 2,527 | 3 | 2,557 | **+2.24** |
| **GitHub Twirp → AuthorizationAPI** | — | ~711 | — | ~711 | **+0.62** |
| CAPI → HMAC (models/completions) | 3 | ~438 | — | ~442 | +0.39 |
| **GitHub Twirp → SweagentdAPI** | 4 | ~350 | 1 | ~355 | **+0.31** |
| GitHub Twirp → RepositoriesAPI | 1 | ~44 | — | ~45 | +0.04 |
| GitHub REST API | 9 | 8 | 2 | 19 | +0.02 |
| Spokes (internal git) | 11 | — | — | 11 | +0.01 |
| GitHub Twirp → UserDetailAPI | 1 | ~3 | — | ~4 | <0.01 |
| CAPI → Session (user/S2S token) | 2 | — | 1 | 3 | <0.01 |
| Limiter Twirp | 2 | — | — | 2 | <0.01 |
| ExP (Experimentation) | 2 | — | — | 2 | <0.01 |
| Aqueduct (job queue) | 2 | — | — | 2 | <0.01 |

### Twirp sub-API detail

| Twirp Backend | Key Operations | Wrapper Spans/Job | Wire Calls/Job | Caching | Notes |
|---|---|---:|---:|---|---|
| **AuthorizationAPI** (→ monolith) | `TokenHasAccess` | ~711 | **~711** | None | 0.65/callback — validates agent token permissions. **No caching — every span is a wire call.** |
| **SweagentdAPI** (→ monolith) | `IsAgentEnabled`, `MintServerToServerTokenForRepo`, `IsBypassActor`, `CreatePullRequest` | ~377 | **~355** | Token: 55-min TTL | IsAgentEnabled (`ConfigurationForRepository`) has **no caching** (~0.32/callback = ~350 wire). MintS2SToken is heavily cached (55-min TTL, ~4 wire calls/job). |
| **RepositoriesAPI** (→ monolith) | `GetRepoByName`, `GetRepoById` | ~45 | **~45** | None | Repo lookups, uncached. |
| **UserDetailAPI** (→ monolith) | `GetCopilotUserDetails` | ~3,263 | **~4** | Context memo + Redis 5-min TTL | ⚠️ Wrapper span starts before cache check (`user_details.go:28`). Count wire misses with `githubtwirp.Client.GetCopilotUserDetails.fetch`; cache hits have no `.fetch` subspan. See [investigation below](#userdetailapi-wrapper-spans-vs-wire-calls). |
| `IsMemoryEnabled` (wrapper) | reads `GetCopilotUserDetails`, checks a field | ~66 | **0 observed additional wire** | Inherits UserDetailAPI cache | The wrapper itself is not a wire call. If it ever misses the UserDetail cache, the child call is counted under UserDetailAPI, not under IsMemoryEnabled ([#11692](https://github.com/github/sweagentd/issues/11692)). |
| **LimiterAPI** (→ Limiter service) | `GetQuotaRemaining` | ~2 | **~2** | None | Only during creation+processing (quota check) |
| **CAPI HMAC** (→ api.githubcopilot.com) | `ListCodingAgentModels`, `ChatCompletions`, `CreateModelSession` | ~442 | **~442** | None | ListModels called by agent runtime via `/models` endpoint |
| **CAPI Session** (→ api.githubcopilot.com) | `CreateSession`, `UpdateSession`, `GetSession` | ~3 | **~3** | None | Session lifecycle (user/S2S token, not HMAC) |

### UserDetailAPI wrapper spans vs wire calls

> ⚠️ **Wrapper spans overstate UserDetailAPI wire calls.** The `githubtwirp.Client.GetCopilotUserDetails` span starts _before_ the cache check (`user_details.go:28`), so APM counts wrapper invocations even when no RPC is made. The newer `.fetch` subspans make this visible: cache hits have no `.fetch` span; cache misses have `githubtwirp.Client.GetCopilotUserDetails.fetch` around the RPC.
>
> **Verified from [trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309):** 9 `GetCopilotUserDetails` spans in one job creation, but only **1 actual API call** (~126ms). The other 8 are cache hits (<0.01ms each).
>
> **Per callback:** 3 invocations (auth middleware + CheckPremiumQuota + GetCustomerID), but only the first touches Redis cache; the other 2 are context memo hits within the same HTTP request.
>
> **Potential optimization:** Move the wrapper tracing span below the cache checks to reduce APM noise, or add a span attribute like `cache_hit:true`. This is no longer required to identify wire calls, because `.fetch` subspans already distinguish cache hits from over-the-wire requests.

> **Each marginal concurrent job adds ~4.47 Redis RPS, ~2.24 CosmosDB RPS, ~0.62 AuthorizationAPI Twirp RPS (wire), ~0.39 CAPI HMAC RPS, ~0.31 SweagentdAPI Twirp RPS (wire), ~0.04 RepositoriesAPI Twirp RPS, and ~0.02 GitHub REST RPS.** UserDetailAPI and IsMemoryEnabled add <0.01 wire RPS (cached).
>
> **Adding 100 concurrent jobs** = +447 Redis, +224 CosmosDB, +62 AuthorizationAPI, +39 CAPI, +31 SweagentdAPI, +4 RepositoriesAPI, +2 REST RPS.
>
> **Adding 1,000 concurrent jobs** = +4,470 Redis, +2,240 CosmosDB, +620 AuthorizationAPI (wire), +390 CAPI, +310 SweagentdAPI (wire), +40 RepositoriesAPI, +17 REST RPS. TokenHasAccess at ~1,665 concurrent: ~62K/min (62% of its 100K/min per-path limit).

**How to use this table:**
- Multiply **+RPS/job** × number of concurrent jobs = total RPS for that system
- Current state: ~665 concurrent jobs → Redis ~2,973 RPS, CosmosDB ~1,490 RPS, Twirp at ~8-10% utilization per [monitor](https://app.datadoghq.com/monitors/275922103)
- Redis is the highest volume but is in-cluster (low latency); CosmosDB is the primary unknown scaling concern; Twirp has ~10× headroom

*Redis (`sweagentd.cache_operation`) confirmed from `internal/cache/rediscachestore.go` — token cache, feature flags, rate limit state.*

---

## RPS Breakdown

**Job timing (7-day averages):** Total = 19min, Execution = 9.3min, Request-to-launched = 4.5min
**Throughput:** 2,105 jobs/hour (0.58 jobs/sec), ~665 concurrent jobs at any time

### Steady-State RPS by Downstream System (wire calls)

| # | Downstream System | Wire Calls/Job | Avg RPS | Peak RPS (~2x) | Calls/Day |
|---:|---|---:|---:|---:|---:|
| 1 | **CosmosDB** | 2,557 | **1,494** | ~2,988 | 129M |
| 2 | **GitHub Twirp → AuthorizationAPI** | 711 | **415** | ~831 | 35.9M |
| 3 | **CAPI HMAC** | 442 | **258** | ~516 | 22.3M |
| 4 | **GitHub Twirp → SweagentdAPI** | 355 | **207** | ~415 | 17.9M |
| 5 | GitHub Twirp → RepositoriesAPI | 45 | 26 | ~53 | 2.3M |
| 6 | GitHub REST API | 19 | 11 | ~22 | 960K |
| 7 | Spokes (S2S) | 11 | 6.4 | ~13 | 556K |
| 8 | GitHub Twirp → UserDetailAPI | ~4 | 2.3 | ~5 | 202K |
| 9 | Other (Limiter, ExP, Aqueduct) | 6 | 3.5 | ~7 | 303K |

### RPS Concentrated in the Callback Phase

| Downstream | Wire Calls/Job in Callbacks | RPS from Callbacks | % of Total RPS |
|---|---:|---:|---:|
| CosmosDB | 2,527 | 1,477 | 99% |
| GitHub Twirp → AuthorizationAPI | 711 | 415 | 100% |
| GitHub Twirp → SweagentdAPI | 350 | 205 | 99% |
| GitHub REST API | 8 | 4.7 | 42% |

### Scaling Projections

| Scale | Concurrent Jobs | CosmosDB RPS | Redis RPS | Twirp utilization (est.) |
|---:|---:|---:|---:|---|
| **1× (current)** | ~665 | 1,494 | 2,973 | ~8-10% (from monitor) |
| **2×** | ~1,330 | 2,988 | 5,945 | ~16-20% |
| **5×** | ~3,325 | 7,470 | 14,863 | ~40-50% |
| **10×** | ~6,650 | 14,940 | 29,726 | ~80-100% ⚠️ |

### Rate Limits to Watch

| System | Known Limit | Current Utilization | Headroom | Source |
|---|---|---:|---:|---|
| Twirp request count (per path) | 100K/min each | **~8-10%** | **~10×** | [Monitor 275922103](https://app.datadoghq.com/monitors/275922103) (server-side) |
| Twirp concurrency (per client) | — | ~9% (spikes 29%) | ~3-10× | Same monitor |
| GitHub content creation secondary limit | ~80 content-generating requests/min, ~500/hour; some endpoints lower | Unknown by installation | **Unknown / hard wall for hot installations** | [GitHub REST rate limits](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api#about-secondary-rate-limits) |
| CosmosDB (RU/s provisioned) | Unknown | Unknown | **Unknown** | Needs investigation |
| Redis (Azure tier) | Unknown | Unknown | **Unknown** | Needs investigation |
| GitHub REST API primary/point secondary | Per installation/user token | Low aggregate | High aggregate | `sweagentd.github.api.*` metrics by `api_target` / `auth_type` |

> ⚠️ **Content creation secondary limits are installation-local hard walls.** Average REST RPS is low, but content-generating operations (workflow dispatch/creation, PR updates, comments, review requests, labels/reactions, GraphQL mutations) are not protected by aggregate headroom. A single hot installation can hit GitHub's content-creation secondary limits even while global REST volume looks healthy, so scale projections need a per-installation view for write-heavy paths.

---

## Key Takeaways

1. **The callback/execution loop dominates.** An estimated ~99% of downstream calls come from the execution phase anchored by ~1,094 callbacks per job. Reducing callback frequency (e.g., batching, longer polling intervals) would likely have the largest impact on downstream pressure.

2. **CosmosDB is likely the #1 scaling concern.** ~2,557 ops/job, ~1,494 RPS estimated. Almost entirely from the callback loop (GetJob, GetCommands, BatchPatchCommands, CreateProgress). All calls are wire calls — no caching layer. **Provisioned capacity is unknown.**

3. **Twirp appears to have ~10× headroom** (not the constraint we initially thought). The monolith's own [server-side limiter monitor](https://app.datadoghq.com/monitors/275922103) reports ~8-10% utilization on the hottest path[^limiter_code]. Our earlier estimates (1.7×, 4×) were wrong because we assumed `github-auth-twirp` (59K/min) was a single path — it's actually spread across multiple RPC methods, each with its own 100K/min bucket. **CosmosDB and Redis limits (unknown) are likely the actual binding constraints.**

4. **UserDetailAPI and IsMemoryEnabled are not primary scaling concerns** despite high wrapper-span counts (~3,263 and ~66/job respectively). UserDetailAPI is heavily cached (context memo + Redis 5-min TTL → estimated ~4 wire calls/job in the job-lifecycle analysis). IsMemoryEnabled itself makes **no direct wire call** — it reads UserDetails and checks a field. Use `.fetch` subspans to verify current cache miss rates before changing these estimates ([#11692](https://github.com/github/sweagentd/issues/11692)).

5. **GitHub REST API is light in aggregate, but content creation is a per-installation hard wall.** Auth is purely Twirp/HMAC, token minting is Twirp + 55-min cache, and REST only fires from result handlers (~0.7% of callbacks). The creation phase is REST-heavier (9 calls/job) but still small globally. However, writes such as workflow creation, PR/comment updates, labels/reactions, and review requests can hit GitHub's content-creation secondary limits for a hot installation before aggregate REST RPS looks concerning.

6. **Spokes is heavier than expected** in creation (11 calls for branch existence checks and blob reads), but fires only once per job.

7. **All trigger types converge** to the same pipeline — no meaningful variance for scaling purposes.

---

## Backing Data Sources

| Source | Link |
|---|---|
| sweagentd dashboard (CPU, memory, aqueduct) | [Dashboard 4wj-b2t-r9p](https://app.datadoghq.com/dashboard/4wj-b2t-r9p/sweagentd) |
| Twirp rate limit monitor (server-side) | [Monitor 275922103](https://app.datadoghq.com/monitors/275922103) |
| API dependency map (call graph) | [docs/api-dependency-map.md](./api-dependency-map.md) |
| Job lifecycle timing | [docs/job-lifecycle-timing.md](./job-lifecycle-timing.md) |
| APM trace (creation+processing) | [Trace 3081dd77](https://app.datadoghq.com/apm/trace/3081dd77496b4304b8e002cc3f9df309) |
| All sweagentd APM spans | [APM explorer](https://app.datadoghq.com/apm/traces?query=service%3Asweagentd) |
| Callback request metric | [sweagentd.agentcallback.requests](https://app.datadoghq.com/metric/explorer?start=1776195084224&end=1776799884224) |
| Job creation metric | [sweagentd.jobs.created](https://app.datadoghq.com/metric/explorer?start=1774965600000&end=1776168000000) |
| Endpoint RPS | [sweagentd.response_count](https://app.datadoghq.com/metric/explorer?start=1774965600000&end=1776168000000) |

### Datadog graph formulas: RPS per job over time

To visualize whether per-job cost is stable (linear) or trending (super-linear), create timeseries graphs with these formulas. Set timeframe to 1 week. If the lines are flat, our linear scaling estimates hold. Use metrics for full-sample aggregate API views; use APM `.fetch` subspans when you need cache-hit vs wire-call distinction or job-lifecycle attribution.

**Graph 1: Calls per Job — Callbacks, Redis, REST** (full-sample metrics)
```
a = sum:sweagentd.agentcallback.requests{*}.as_count()
b = sum:sweagentd.jobs.created{*}.as_count()
c = sum:sweagentd.cache_operation{*}.as_count()
d = sum:sweagentd.github.api.request{api_target:public_rest}.as_count()
e = sum:sweagentd.github.api.request{api_target:internal_rest}.as_count()
Formulas: a/b (Callbacks/job), c/b (Redis/job), (d+e)/b (REST/job, aggregate incl. non-job)
```

**Graph 2: API Calls per Job — by API target** (full-sample aggregate metrics)
```
a = sum:sweagentd.github.api.request{*} by {api_target}.as_count()
b = sum:sweagentd.jobs.created{*}.as_count()
Formula: a/b
```
Expected targets include `internal_twirp_api`, `internal_twirp_auth`, `internal_twirp_limiter`, `internal_capi`, `public_rest`, `internal_rest`, `public_graphql`, and `internal_graphql`; not every target has data in every window. If `api_target:N/A` appears, the feature flag was off for that sample or the client did not attach the new tags.

**Graph 3: API error rate by target and auth type**
```
a = sum:sweagentd.github.api.request{*} by {api_target,auth_type}.as_count()
b = sum:sweagentd.github.api.error{*} by {api_target,auth_type}.as_count()
Formula: b/a
```

**Graph 4: Rate-limit headroom by API target**
```
a = avg:sweagentd.github.api.rate_limit_remaining{*} by {api_target,auth_type,resource}
b = sum:sweagentd.github.api.rate_limit_exceeded{*} by {api_target,auth_type}.as_count()
```
`rate_limit_exceeded` only appears when we actually hit a primary or secondary limit, so no data is good data for that series.

**APM span check: wrapper spans vs fetch spans**
```
Wrapper invocations: service:sweagentd resource_name:githubtwirp.Client.GetCopilotUserDetails
Wire misses: service:sweagentd resource_name:githubtwirp.Client.GetCopilotUserDetails.fetch
```
For lower-level HTTP wire counts, use either `POST` or `HTTP POST` child spans consistently and group by `rpc.method`; do not add both, because the custom telemetry span and otelhttp span overlap for the same outbound request.

**Graph 5: HTTP Pod CPU vs Limit** (is CPU tracking job volume?)
```
a = max:kubernetes.cpu.usage.total{kube_namespace:sweagentd-production,stamp:dotcom,kube_deployment:sweagentd}
b = avg:kubernetes.cpu.limits{kube_namespace:sweagentd-production,stamp:dotcom,kube_deployment:sweagentd} * 1e9
```

**Graph 6: Twirp Limiter % — server-side ground truth**
```
a = max:api.limiter.gauge.percent{key:sweagentd,limiter:twirp-request-count-by-client-and-path,stamp:dotcom} * 100
b = max:api.limiter.gauge.percent{key:sweagentd,limiter:twirp-concurrent-by-client,stamp:dotcom} * 100
```
