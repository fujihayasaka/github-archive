# sweagentd — Data Flow & Dependency Diagram

Visual companion to [`api-dependency-map.md`](./api-dependency-map.md).

---

## High-Level Request Flow

How a request enters the system and which external services are touched.

The primary external request path is **GLB → CAPI → sweagentd HTTP API**: user requests hit the GitHub Load Balancer, route through CAPI (the Copilot API gateway), which calls sweagentd's HTTP endpoints with user tokens. Internal services — **github/github (dotcom)** and **copilot-mission-control (CMC)** — call sweagentd's **Twirp RPC** server directly with HMAC auth, bypassing CAPI. GitHub-originated **Hydro events** (delivered via Kafka) are consumed by sweagentd's Hydro consumer/dispatcher goroutines, which filter and enqueue them as **Aqueduct EventJob** messages for asynchronous processing. Note: sweagentd does **not** receive HTTP webhooks directly — all GitHub platform events arrive through Hydro.

```mermaid
flowchart LR
    classDef entrypoint fill:#4a90d9,stroke:#2c5f8a,color:#fff
    classDef gateway fill:#9b59b6,stroke:#7d3c98,color:#fff
    classDef core fill:#5cb85c,stroke:#3d8b3d,color:#fff
    classDef corehttp fill:#2ecc71,stroke:#27ae60,color:#fff
    classDef worker fill:#16a085,stroke:#0e6655,color:#fff
    classDef external fill:#f0ad4e,stroke:#c7922a,color:#000
    classDef monolith fill:#e67e22,stroke:#d35400,color:#fff
    classDef separate fill:#d4ac0d,stroke:#b7950b,color:#000
    classDef downstream fill:#1abc9c,stroke:#16a085,color:#fff

    %% ── Primary inbound path ──
    GLB["<b>GLB</b><br/>GitHub Load Balancer"]:::entrypoint
    CAPI_GW["<b>CAPI</b><br/>Copilot API gateway"]:::gateway
    DOTCOM["<b>github/github</b><br/>(dotcom callers)"]:::entrypoint
    CMC["<b>copilot-mission-control</b><br/>(CMC)"]:::entrypoint

    subgraph sweagentd
        SW_TWIRP["<b>Twirp Server</b><br/>(internal — cmd/twirp)<br/>CreateJob, CreateAssignment,<br/>CreateCommand, CancelJob, …"]:::core
        SW_HTTP["<b>HTTP API</b><br/>(public — cmd/http)<br/>jobapi, agenthttp,<br/>agentcallback"]:::corehttp
        SW_AGENT["<b>AgentJob worker</b><br/>(goroutines in cmd/http)<br/>ProcessJob execution"]:::worker
        SW_EVENT["<b>EventJob worker</b><br/>(goroutines in cmd/http<br/>+ cmd/worker)<br/>Hydro event handlers"]:::worker
        SW_API["<b>APIJob worker</b><br/>(goroutines in cmd/http)<br/>async job processing"]:::worker
    end

    GLB ==>|"user request"| CAPI_GW
    CAPI_GW ==>|"HTTP API (user token)"| SW_HTTP
    DOTCOM ==>|"Twirp RPC (HMAC)"| SW_TWIRP
    CMC ==>|"Twirp RPC (HMAC)<br/>CreateAssignment,<br/>CreateJobForAssignment,<br/>CreateCommand, CancelJob,<br/>GetJobBySessionID,<br/>UpdateAssignment"| SW_TWIRP
    CMC ==>|"HTTP API (user token)<br/>POST /jobs, GET /status"| SW_HTTP

    %% ── Hydro events flow: Hydro → Dispatcher → Aqueduct → workers ──
    Hydro["<b>Hydro / Kafka</b><br/>(GitHub platform events)"]:::entrypoint
    AQ["<b>Aqueduct</b><br/>(job queue)"]:::external
    DISPATCH["<b>Hydro consumer /<br/>dispatcher</b><br/>(cmd/http, cmd/worker,<br/>cmd/scheduler)"]:::worker

    Hydro -->|"Hydro events"| DISPATCH
    DISPATCH -->|"enqueue EventJob"| AQ
    SW_HTTP -->|"enqueue AgentJob / APIJob"| AQ
    SW_TWIRP -->|"enqueue AgentJob"| AQ
    AQ -->|"consume"| SW_AGENT & SW_EVENT & SW_API

    %% ── github/github monolith (internal APIs) ──
    subgraph ghapis [" <b>github/github</b> (monolith — internal APIs) "]
        GH_REST["<b>GitHub REST / GraphQL</b><br/>(api.github.com)"]:::external
        GH_TWIRP["<b>Twirp APIs</b><br/>UserDetail, Sweagentd,<br/>Authorization, Repositories"]:::monolith
        MINT["<b>MintServerToServerTokenForRepo</b><br/>(SweagentdAPI Twirp RPC)"]:::monolith
    end

    %% ── Separate services (not in monolith) ──
    LIMITER["<b>copilot-limiter</b><br/>(LimiterTwirpAPIURL)<br/><i>GetQuotaRemaining</i>"]:::separate
    BILLING["<b>Billing Platform</b><br/>(BillingClientURL)"]:::separate

    %% ── Other outbound deps ──
    CAPI_OUT["<b>CAPI</b><br/>(api.githubcopilot.com)<br/>model + sessions"]:::external
    EXP["<b>ExP</b><br/>(experimentation)"]:::external
    SPOKES["<b>Spokes</b><br/>(internal git)"]:::external

    %% ── Downstream consumers of Hydro events emitted by sweagentd ──
    DOWNSTREAM["<b>Downstream consumers</b><br/>(e.g. CMC, VS Code)"]:::downstream

    SW_TWIRP -->|"HMAC"| GH_TWIRP & MINT
    SW_HTTP -->|"HMAC"| GH_TWIRP & MINT
    SW_AGENT -->|"S2S / user token"| GH_REST
    SW_AGENT -->|"HMAC"| GH_TWIRP
    SW_EVENT -->|"S2S token"| GH_REST
    SW_EVENT -->|"HMAC"| GH_TWIRP & MINT
    SW_API -->|"HMAC"| GH_TWIRP & MINT

    SW_HTTP -->|"HMAC"| LIMITER
    SW_TWIRP -->|"HMAC"| LIMITER
    SW_HTTP -->|"HMAC"| BILLING

    SW_AGENT -->|"HMAC / user token"| CAPI_OUT
    SW_EVENT -->|"HMAC / user token"| CAPI_OUT
    SW_AGENT -->|"no auth"| EXP
    SW_AGENT -->|"internal S2S"| SPOKES

    %% ── Outbound Hydro events (job progress, job updates) ──
    SW_AGENT -.->|"Hydro publish<br/>JobUpdated, JobProgress"| DOWNSTREAM
    SW_EVENT -.->|"Hydro publish<br/>JobUpdated"| DOWNSTREAM
    SW_HTTP -.->|"Hydro publish<br/>JobUpdated"| DOWNSTREAM
```

---

## Twirp Sub-API Breakdown

All use HMAC auth — most target protobuf services inside the github/github monolith, but **copilot-limiter** and **Billing Platform** are separate services.

```mermaid
flowchart TD
    classDef core fill:#5cb85c,stroke:#3d8b3d,color:#fff
    classDef twirp fill:#8e44ad,stroke:#6c3483,color:#fff
    classDef mint fill:#e67e22,stroke:#d35400,color:#fff
    classDef separate fill:#d4ac0d,stroke:#b7950b,color:#000

    SW["<b>sweagentd</b><br/>githubtwirp.Client"]:::core

    subgraph "github/github (monolith) — GitHubTwirpAPIURL"
        UD["<b>UserDetailAPI</b><br/>copilot-twirp/users/v1<br/><i>GetCopilotUserDetails</i>"]:::twirp
        SA["<b>SweagentdAPI</b><br/>sweagentd/v1<br/><i>ConfigurationForRepository</i><br/><i>GetUserToServerToken</i><br/><i>IsBypassActor</i>"]:::twirp
        MINT["<b>SweagentdAPI</b><br/><i>MintServerToServerTokenForRepo</i><br/>⚡ mints S2S installation tokens"]:::mint
        AA["<b>AuthorizationAPI</b><br/>copilot-api/twirp/core/v1<br/><i>BatchControlAccess</i>"]:::twirp
        RA["<b>RepositoriesAPI</b><br/>github-proto/repositories/v1<br/><i>FindRepositories</i><br/><i>FindRepositoriesByName</i>"]:::twirp
    end

    subgraph "Separate services"
        LA["<b>copilot-limiter</b><br/>LimiterTwirpAPIURL<br/><i>GetQuotaRemaining</i>"]:::separate
        BC["<b>Billing Platform</b><br/>BillingClientURL"]:::separate
    end

    SW -->|"HMAC"| UD
    SW -->|"HMAC"| SA
    SW -->|"HMAC → returns S2S token"| MINT
    SW -->|"HMAC"| AA
    SW -->|"HMAC"| RA
    SW -->|"HMAC (LimiterTwirpHMACKey)"| LA
    SW -->|"HMAC (BillingClientHMACKey)"| BC
```

---

## Token Minting & Auth Flow

How sweagentd obtains tokens to call the GitHub REST/GraphQL API.

```mermaid
flowchart TD
    classDef core fill:#5cb85c,stroke:#3d8b3d,color:#fff
    classDef token fill:#3498db,stroke:#2471a3,color:#fff
    classDef external fill:#f0ad4e,stroke:#c7922a,color:#000
    classDef mint fill:#e67e22,stroke:#d35400,color:#fff

    SW["<b>sweagentd</b>"]:::core

    subgraph "Token Paths"
        U["<b>User/OAuth token</b><br/>forwarded from caller"]:::token
        S2S["<b>Installation/S2S token</b><br/>minted via Twirp"]:::token
        JWT["<b>App JWT</b><br/>(agentic apps only)"]:::token
    end

    subgraph "github/github (monolith)"
        MINT["<b>SweagentdAPI</b><br/><i>MintServerToServerTokenForRepo</i><br/>HMAC auth → returns S2S token"]:::mint
    end

    GH["<b>GitHub REST / GraphQL</b>"]:::external

    SW -->|"NewClientForUser()"| U
    SW -->|"NewClientFromRepo()"| S2S
    SW -->|"agenticapp.mintToken()"| JWT

    S2S --->|"HMAC request"| MINT
    MINT --->|"S2S token"| S2S

    U -->|"Bearer token"| GH
    S2S -->|"Bearer token"| GH
    JWT -->|"JWT → Apps API"| GH
```

---

## CAPI Dual-Mode Auth

CAPI is called two different ways depending on the operation.

```mermaid
flowchart LR
    classDef core fill:#5cb85c,stroke:#3d8b3d,color:#fff
    classDef hmac fill:#e74c3c,stroke:#c0392b,color:#fff
    classDef user fill:#3498db,stroke:#2471a3,color:#fff
    classDef capi fill:#f0ad4e,stroke:#c7922a,color:#000

    SW["<b>sweagentd</b>"]:::core

    subgraph "HMAC Client (integration-level)"
        H1["ChatCompletions<br/><i>stacked PR titles</i>"]:::hmac
        H2["ListCodingAgentModels"]:::hmac
        H3["CreateModelSession"]:::hmac
    end

    subgraph "User Client (per-job)"
        U1["CreateSession"]:::user
        U2["GetSession"]:::user
        U3["UpdateSession"]:::user
    end

    CAPI["<b>CAPI</b><br/>api.githubcopilot.com"]:::capi

    SW -->|"HMAC + Integration-Id"| H1 & H2 & H3
    SW -->|"Bearer user/S2S token"| U1 & U2 & U3

    H1 & H2 & H3 --> CAPI
    U1 & U2 & U3 --> CAPI
```

---

## Job Lifecycle: End-to-End

How a typical coding-agent job flows through the system.

```mermaid
sequenceDiagram
    participant User as User / GitHub UI
    participant GLB as GLB
    participant CAPI_GW as CAPI<br/>(gateway)
    participant CMC as copilot-mission-<br/>control (CMC)
    participant SW as sweagentd<br/>(HTTP API)
    participant Worker as sweagentd<br/>(AgentJob worker)
    participant Twirp as github/github<br/>(monolith Twirp)
    participant Limiter as copilot-limiter
    participant GH as GitHub REST /<br/>GraphQL
    participant CAPI as CAPI<br/>(model/sessions)
    participant AQ as Aqueduct
    participant Hydro as Hydro
    participant Spokes as Spokes
    participant EXP as ExP
    participant Downstream as Downstream<br/>(CMC, VS Code, …)

    User->>GLB: Create coding agent job
    GLB->>CAPI_GW: route request (user token)
    CAPI_GW->>SW: HTTP API (user token)

    Note over SW: Middleware: auth + permission check
    SW->>Twirp: AuthorizationAPI.BatchControlAccess (HMAC)
    SW->>GH: GET /repos/.../collaborators/.../permission (user token)

    Note over SW: Enablement + quota
    SW->>Twirp: SweagentdAPI.ConfigurationForRepository (HMAC)
    SW->>Twirp: UserDetailAPI.GetCopilotUserDetails (HMAC)
    SW->>Limiter: GetQuotaRemaining (HMAC)
    Limiter-->>SW: quota OK

    Note over SW: Mint installation token (inside github/github)
    SW->>Twirp: SweagentdAPI.MintServerToServerTokenForRepo (HMAC)
    Note over Twirp: github/github mints S2S token<br/>for the app installation on repo
    Twirp-->>SW: S2S installation token

    Note over SW: Queue for async processing
    SW->>AQ: Enqueue APIJob (API key)
    AQ-->>SW: Job accepted

    Note over AQ,Worker: Aqueduct worker goroutine consumes job
    AQ->>Worker: Deliver APIJob

    Note over Worker: Rate limit + quota check
    Worker->>Twirp: UserDetailAPI.GetCopilotUserDetails (HMAC)
    Worker->>Limiter: GetQuotaRemaining (HMAC)
    Limiter-->>Worker: quota OK

    Note over Worker: Build job
    Worker->>Twirp: MintServerToServerTokenForRepo (HMAC)
    Twirp-->>Worker: S2S token
    Worker->>GH: GET /repos/{owner}/{repo} (S2S token)
    Worker->>EXP: Feature assignment (no auth)
    Worker->>Spokes: CreateBranch + CreateEmptyCommit (S2S)
    Worker->>GH: Create PR (S2S token)
    Worker->>CAPI: CreateSession (user token)

    Note over Worker: Queue agent execution
    Worker->>AQ: Enqueue AgentJob (API key)
    Worker->>Hydro: Publish JobUpdated event
    Hydro-->>Downstream: JobUpdated (job queued)

    Note over AQ,Worker: AgentJob worker picks up job
    AQ->>Worker: Deliver AgentJob
    Worker->>Limiter: Rate limit check (HMAC)
    Limiter-->>Worker: OK
    Worker->>GH: Create workflow dispatch (S2S token)

    Note over Worker: On workflow completion<br/>(Hydro event → EventJob)
    Worker->>GH: List workflow jobs (S2S token)
    Worker->>CAPI: UpdateSession (user token)
    Worker->>Hydro: Publish JobUpdated event
    Hydro-->>Downstream: JobUpdated (job completed)
    Worker->>GH: Request reviewers (S2S token)

    Note right of CMC: CMC also initiates jobs via<br/>Twirp (CreateAssignment,<br/>CreateJobForAssignment,<br/>CreateCommand) and HTTP API<br/>(POST /jobs, GET /status)
```

---

## Running Job: Agentic Loop with Progress Updates

Once an agent job has been launched (via `CreateDynamicWorkflowRun`), the agent runtime executes inside a GitHub Actions sandbox. This diagram shows a single iteration of the agentic loop — the agent calls back to sweagentd with progress/results, and sweagentd finalizes the job when the workflow completes.

There are two distinct inbound paths:
1. **Runtime callback path** — the agent in the sandbox posts progress and partial results to sweagentd's `agentcallback` HTTP endpoint during execution.
2. **Workflow completion path** — when the Actions workflow finishes, a `WorkflowRunExecution` Hydro event is consumed by sweagentd's EventJob handler, which finalizes the job.

```mermaid
sequenceDiagram
    participant Agent as Agent runtime<br/>(Actions sandbox)
    participant SW as sweagentd<br/>(HTTP API /<br/>agentcallback)
    participant EventW as sweagentd<br/>(EventJob worker)
    participant Twirp as github/github<br/>(monolith Twirp)
    participant GH as GitHub REST /<br/>GraphQL
    participant CAPI as CAPI<br/>(sessions)
    participant Hydro as Hydro
    participant AQ as Aqueduct
    participant Downstream as Downstream<br/>(CMC, VS Code, …)

    Note over Agent,SW: ── Runtime callback path ──

    rect rgb(240, 248, 255)
        loop Each agentic loop iteration
            Agent->>SW: POST /callback (progress update)
            SW->>CAPI: UpdateSession — progress (user token)
            SW->>Hydro: Publish JobProgress event
            Hydro-->>Downstream: JobProgress (live update)

            Agent->>SW: POST /callback (partial result / PR metadata)
            Note over SW: Persist result metadata in DB<br/>(e.g. PR creation info for CMC)
            SW->>CAPI: UpdateSession — status (user token)
            SW->>Hydro: Publish JobUpdated event
            Hydro-->>Downstream: JobUpdated
        end
    end

    Note over Agent,EventW: ── Workflow completion path ──

    rect rgb(255, 245, 238)
        Agent->>GH: Workflow run completes
        GH->>Hydro: WorkflowRunExecution event
        Hydro->>AQ: Enqueue EventJob
        AQ->>EventW: Deliver EventJob

        Note over EventW: on_workflow_run_completed.go
        EventW->>Twirp: MintServerToServerTokenForRepo (HMAC)
        Twirp-->>EventW: S2S token
        EventW->>GH: List workflow jobs (S2S token)
        EventW->>GH: GET workflow run artifacts (S2S token)
        EventW->>CAPI: UpdateSession — finalize (user token)
        EventW->>GH: Request reviewers (S2S token)
        EventW->>Hydro: Publish JobUpdated event (completed)
        Hydro-->>Downstream: JobUpdated (final status)
    end
```

> **Note:** This is a simplified view of a single job iteration. In practice, the agent may run multiple loop iterations within one workflow run, and the workflow may be re-dispatched for follow-up work (e.g., responding to PR review comments). For the full end-to-end lifecycle including job creation, see [Job Lifecycle: End-to-End](#job-lifecycle-end-to-end) above.
