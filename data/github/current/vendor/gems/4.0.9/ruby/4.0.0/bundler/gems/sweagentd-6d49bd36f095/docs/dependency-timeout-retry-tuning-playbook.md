# Dependency Timeout/Retry Tuning Playbook

This playbook describes a reusable process for tuning dependency timeouts and retries using production telemetry. It is written to be service-agnostic so any service owner can use the same process for their own dependencies.

## Goals

- Reduce user-facing tail-latency amplification during dependency incidents
- Keep false timeouts low during healthy operation
- Make timeout/retry tuning evidence-based and repeatable
- Create a path to future automation

## Signals to collect (for any dependency)

1. **Client-observed latency** from the caller service (p95, p99, and high-tail percentiles)
2. **Dependency server-side latency and saturation** to separate caller effects from dependency-side degradation
3. **Retry behavior** (retry attempt volume, retry-exhausted signals, retry rate vs request volume)
4. **Call fanout per request path** (how many dependency calls each top endpoint performs)
5. **Caller user-impact metrics** (endpoint latency and error rate)

## Tuning guidance

1. Select a healthy baseline window and a stressed/incident window.
2. Set timeout from healthy client-observed tail latency:
   - default target: **p99.9**
   - consider **p99.99** when dependency behavior is stable and false timeouts are more expensive than slower failure
   - avoid anchoring on incident spikes
3. Keep retries intentionally small for synchronous user-facing paths.
4. Explicitly account for fanout: multiple dependency calls per request can compound retry cost quickly.
5. Prefer predictable failure over long tail amplification when the dependency is degraded.
6. Roll out gradually (canary first) with explicit rollback criteria.

## Example metrics (illustrative)

These are examples from sweagentd + limiter to illustrate categories. Other services should substitute their own dependency metrics.

- Client latency: `http_request_duration{client_name:limiter-twirp}`
- Retry attempts: `sweagentd.github.api.retry{client_name:limiter-twirp}`
- Client request volume: `sweagentd.github.api.request{client_name:limiter-twirp}`
- Dependency server duration: `copilot_limiter.request_duration{twirp_service:copilotlimiterapi}`
- Trace-derived server duration: `trace.copilot_limiter.server.duration{service:copilot-limiter}`

## Agent prompt template for service owners

Use this prompt with an agent and replace placeholders:

```text
Analyze timeout/retry tuning for <service> calling <dependency>.

Use Datadog to gather:
- client-side latency percentiles for calls from <service> to <dependency>
- dependency server-side latency/saturation
- retry attempts and retry-exhausted signals
- request volume and fanout by hot request paths
- user-facing latency/error impact in the caller

Compare healthy vs stressed windows, recommend timeout/retry settings
(timeout anchored at p99.9 or p99.99 of healthy client latency), explain tradeoffs,
and produce:
1) recommendation
2) rollout and rollback criteria
3) exact query links
4) a PR-ready config diff
```

## Future automation vision

1. Auto-discover dependency edges from tracing and code ownership metadata.
2. Auto-generate recurring dependency tuning reports (healthy vs stressed windows).
3. Auto-propose timeout/retry changes in draft PRs with supporting evidence.
4. Auto-run canary guardrails and rollback when predefined regression conditions trigger.
5. Feed rollout outcomes back into tuning recommendations to improve defaults over time.

## Expected result

A standard, service-agnostic tuning workflow that can be run by humans or agents, reducing incident blast radius while preserving good steady-state behavior.
