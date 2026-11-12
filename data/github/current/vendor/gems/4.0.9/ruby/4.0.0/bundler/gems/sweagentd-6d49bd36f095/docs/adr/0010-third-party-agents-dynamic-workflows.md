# ADR: Third-Party Agents Dynamic Workflow Triggering

**Status:** Proposed
**Date:** 2026-01-29
**Author:** @arthurnn
**Stakeholders:** @josebalius, @heavymachinery, @SrRyan, @thyeggman

---

## Context

GitHub is expanding the Copilot Coding Agent (CCA) platform to support third-party (3P) agents through AgentsHQ. Currently, privileged GitHub Apps can trigger Dynamic Workflow runs directly via the internal Dynamic Workflow API. This capability is gated by the `actions_dynamic_workflows: true` permission on the app.

As we onboard third-party agents, granting them direct access to trigger Dynamic Workflows poses significant security risks.

---

## Decision

**We will not grant third-party agents the capability to trigger Dynamic Workflow runs directly.**

Instead, third-party agent workflows will be triggered through the existing SWEAgent (Copilot Coding Agent) infrastructure, which will act as a trusted proxy:

1. SWEAgent triggers the Dynamic Workflow using its own credentials
2. The 3P agent's bot is passed as the `actor` parameter
3. Workflow paths are prefixed with `dynamic/agents/` to distinguish 3P agent workflows
4. Launch applies the same policies as existing 3P apps and CCA (no policy changes required)

---

## Current State

### How Dynamic Workflows Work Today

```
┌─────────────┐                              ┌─────────────┐
│ Privileged  │  POST /internal/.../dynamic  │ github/github│
│ GitHub App  │ ─────────────────────────────▶│             │
│ (e.g., CCA) │   Auth: App's own token      └──────┬──────┘
└─────────────┘                                     │
                                                    ▼
                                              ┌───────────┐
                                              │  Launch   │
                                              └───────────┘
```

- Apps with `actions_dynamic_workflows: true` can call the Dynamic Workflow API directly
- The authenticated app becomes the `actor` and `integration_name` is derived from the app's identity
- Launch applies policies based on exact path matching (e.g., `dynamic/copilot-swe-agent/copilot`)

### The Problem

If we grant 3P agents the `actions_dynamic_workflows` permission:

- Each 3P agent app could directly trigger workflows across all repositories where it's installed
- A compromised 3P app private key could be used to trigger malicious workflows at scale
- We have limited control over what workflows are triggered and how

---

## Proposed State

```
┌─────────────┐
│  3P Agent   │  Private key does NOT grant
│  GitHub App │  access to Dynamic Workflow API
│ (private key)│ ─────────── ✗ ──────────────▶ (blocked)
└─────────────┘

┌─────────────┐   POST /internal/.../dynamic  ┌─────────────┐
│  sweagentd  │ ────────────────────────────▶ │ github/github│
│             │   Auth: SWEAgent token        │  (DW API)   │
│             │   Body: { actor: 3P bot }     └──────┬──────┘
└─────────────┘                                      │
                                                     ▼
                                               ┌───────────┐
                                               │  Launch   │
                                               └───────────┘
```

Key changes:
- 3P agents do **not** have `actions_dynamic_workflows` permission
- All 3P agent workflow triggers go through sweagentd (using existing Twirp endpoints, no new endpoints required)
- sweagentd uses its own (SWEAgent) credentials to call the Dynamic Workflow API
- The 3P agent's bot identity is passed as a parameter, not derived from authentication

---

## Security Analysis

### Threat: Compromised 3P App Private Key

| Scenario | Without This Change | With This Change |
|----------|---------------------|------------------|
| Attacker obtains 3P app private key | Can trigger workflows on ALL installed repos | Cannot trigger workflows (no permission) |
| Blast radius | Entire install base of the 3P app | None - must compromise sweagentd |

**This is the primary threat this architecture mitigates.**

### Threat: Actor Impersonation

With the proposed design, the Dynamic Workflow API accepts an `actor` parameter. This introduces a new risk: what if a caller passes a fake actor?

**Mitigations:**

1. **Restricted to SWEAgent only** - Only the SWEAgent app can use actor override. Other callers are rejected.

2. **Actor must be a bot** - Human users cannot be impersonated. Only bot accounts are accepted.

3. **AgenticApp validation** - We will use the AgenticApp layer in github/github to query the actor and the repository, ensuring the 3P integration matches the actor and is installed on the target repository.

4. **Internal-only attack surface** - sweagentd is not internet-accessible. It can only be reached via internal Twirp calls from github/github. An attacker would need to compromise internal infrastructure, not just a 3P app key.

5. **Audit logging** - All actor overrides are logged with both the caller identity and the impersonated actor.

6. **Feature flag kill switch** - The entire feature can be disabled instantly if issues are discovered.

### Why This Is Secure

The architecture shifts trust from "any 3P app with permission" to "only sweagentd with internal access":

| Trust Boundary | Old Model | New Model |
|----------------|-----------|-----------|
| Who can trigger? | Any app with `actions_dynamic_workflows` | Only sweagentd |
| Attack surface | Internet (any 3P app) | Internal network only |
| Compromised key impact | Full access to installed repos | No direct access |
| Rate limiting | Per-app | Centralized in sweagentd |

---

## Alternatives Considered

### Alternative 1: Grant 3P Apps Direct Access with Restrictions

Grant `actions_dynamic_workflows` to 3P apps but add restrictions (rate limits, workflow content validation, etc.).

**Rejected because:**
- A compromised key still has direct API access
- Restrictions are reactive, not preventive
- Harder to revoke access for a single compromised app

### Alternative 2: Separate Queue/Service for 3P Agents

Create a dedicated queue and service for 3P agent workflows, separate from sweagentd.

**Rejected because:**
- Adds operational complexity
- Duplicates infrastructure
- Current rate limits (2 parallel CAPI requests) already protect against thundering herd
- No clear benefit over routing through sweagentd

---

## Consequences

### Positive

- **Reduced blast radius** - Compromised 3P app keys cannot trigger workflows
- **Centralized control** - All 3P agent workflows flow through sweagentd
- **Consistent policies** - Launch applies same policies to all 3P agents via path prefix matching
- **Audit trail** - Clear logging of who triggered what on behalf of whom

### Negative

- **Added complexity** - Actor override mechanism in the API
- **Dependency on sweagentd** - 3P agents cannot function if sweagentd is down
- **Latency** - Extra hop through sweagentd (minimal impact expected)

### Neutral

- **Billing unchanged** - 3P agents are billed same as CCA (billing not bypassed)

---

## Workflow Approval Compatibility

GitHub has an existing mechanism where bot-triggered workflows can require user approval before running. This protects against compromised bots triggering malicious CI pipelines.

**Key insight:** Dynamic workflows are intentionally exempt from this approval check. When a user explicitly invokes an agent (e.g., assigns an issue to CCA), they've already expressed intent—requiring approval again would be redundant.

However, **side-effect workflows still require approval**. If an agent creates a PR or pushes code that triggers CI, those workflows enter "action required" state until a maintainer approves them.

**This architecture preserves that behavior:**
- 3P agent's main dynamic workflow → runs without additional approval (user already invoked it)
- Workflows triggered by agent's actions (PRs, pushes) → require user approval

### Out of Scope: Capability Model Changes

Currently, `actions_require_workflow_approval` is a capability only available to **privileged apps** (apps defined in code via `lib/apps/privileged/`). User-created apps (Integration table) do not have access to this capability system.

**Today, this is safe:** The initial 3P agents (Claude, Codex, etc.) are defined as privileged apps and will have this capability properly configured.

In the future, 3P agents will be dynamically created by users (AgenticApp), not defined as privileged apps. There is separate, broader work underway to review and refactor all agent-related capabilities to work with AgenticApp and dynamically-created agents.

**This ADR does not cover capability changes** — it focuses only on the Dynamic Workflow triggering architecture.

---

## References

- [Issue #8475](https://github.com/github/sweagentd/issues/8475) - Original proposal
- [Dynamic Workflow Config](https://github.com/github/launch/blob/main/pkg/dynamicworkflow/config.go) - Launch policy implementation
- [CopilotSweAgentJobSecretsProvider](https://github.com/github/github/blob/master/app/api/internal/twirp/actions/core/v1/job_secrets_provider/copilot_swe_agent_job_secrets_provider.rb) - Secrets provider reference
