# Monitoring Dependencies

Tracking issue: [#11501 — Metrics, dashboards, and monitors for dependency health](https://github.com/github/sweagentd/issues/11501)

We want client-side metrics for all of our dependency interactions so it's easy and fast to understand what might be degraded or degrading. This doc lists each dependency, the monitoring we have in place, and what's still needed.

## Moda / Kubernetes

**Tracking issues:** [#11502](https://github.com/github/sweagentd/issues/11502), [#11393](https://github.com/github/sweagentd/issues/11393)
**Status:** ✅ Adopted

We adopted the [standard Moda Kubernetes monitors](https://github.com/github/datadog-monitoring/blob/main/templates/org-wide/components/monitors/generic-moda-monitors-for-services.yaml.erb) via [datadog-monitoring#49657](https://github.com/github/datadog-monitoring/pull/49657). This gives us 8 monitors covering pod lifecycle, container health, and deployment availability across all production namespaces including Proxima stamps.

### Monitors

| Monitor | Priority | What it catches |
|---------|----------|-----------------|
| OOMKilled events | P2 | Containers killed for exceeding memory limits |
| Unavailable replicas | P2 | >20% of deployment replicas unavailable |
| No containers running | P2 | Zero containers running in namespace |
| No pods ready | P2 | Zero pods ready in namespace |
| High container restart rate | P3 | Elevated container restart frequency |
| High pods waiting rate | P2 | Pods stuck in ImagePullBackOff, CrashLoopBackOff, etc. |
| High pod termination rate | P3 | Elevated pod terminations |
| High pod eviction rate | P3 | Pod evictions due to resource pressure or node issues |

### Coverage

- **Namespace pattern:** `sweagentd-prod*` — wildcarded to cover all 7 production namespaces (IAD + 6 Proxima stamps)
- **Team:** `team:coding-agent-core-team`
- **Playbook:** [coding-agent playbook](https://ops.githubapp.com/docs/playbooks/copilot/coding-agent)
- Monitors use percentages or low absolute counts and group `by {kube_namespace, stamp}` so each stamp is evaluated independently

### Pre-existing custom monitors

sweagentd also has custom `container_restarts` and `container_termination_error` monitors, plus Proxima-specific business-logic monitors (`proxima-agent-callback-*`, `proxima-aqueduct-*`). The Moda template provides broader, standardized infra coverage. We may deduplicate if the MODA monitors prove sufficient.

## GitHub API

**Tracking issue:** [#11505](https://github.com/github/sweagentd/issues/11505)
**Status:** 🔲 TODO

<!-- Covers: public REST, public GraphQL, internal REST, internal GraphQL, internal Twirp.
     Needs: rate limit utilization, request latency, headroom tracking, per-API-type dashboard. -->

## Copilot Limiter

**Tracking issue:** [#11437](https://github.com/github/sweagentd/issues/11437)
**Status:** ✅ Done

sweagentd calls copilot-limiter via Twirp RPCs twice per API request path (in `CreateJobForAssignment`). After an [availability incident](https://github.com/github/availability/issues/5351) revealed compounding tail latency, we tuned timeouts/retries and added retry metrics.

### What was done

- **Timeout tuning** ([#11394](https://github.com/github/sweagentd/pull/11394)): Reduced `LimiterTwirpRequestTimeoutMs` from 1000ms to 100ms (P99.95) and `RetryMax` from 3 to 2. Prevents multi-second tail latencies from compounding across the two limiter calls per request.
- **Retry metrics** ([#11426](https://github.com/github/sweagentd/pull/11426)): Emits `sweagentd.github.api.retry` on retry attempts with tags: `client_name`, `retry_number`, `max_attempts`. Gated behind feature flag `copilot_swe_agent_limiter_retry_metrics`.
- **Dashboard:** [Limiter Twirp outbound HTTP metrics notebook](https://app.datadoghq.com/notebook/14272118/sweagentd-limiter-twirp-outbound-http-metrics)

## Redis

**Tracking issue:** [#11549](https://github.com/github/sweagentd/issues/11549)
**Status:** 🟡 In progress ([datadog-monitoring#49746](https://github.com/github/datadog-monitoring/pull/49746))

sweagentd connects to 9 Redis instances (1 IAD GitHub-managed, 8 Azure Redis across Proxima stamps) for caching and circuit breaking. Client-side pool metrics (`sweagentd.redis.client.connections.*`, 26 metrics) are already emitting via `redismetrics.StartRedisMetricsWithCustomTagsFn()`.

### Server-side monitors

- **IAD Redis** (`db-redis-sweagentd-rw`): Already covered by db-redis platform team monitors (memory 80%, CPU 90%, availability).
- **Azure Redis (Proxima stamps)**: Enrolled in the `azure-redis` template, which auto-generates server-load, memory, client-limit, throughput, error-rate, failover, and key-eviction monitors for all 7 Proxima stamp instances.
- **AMR instance** (`amr-sweagentd-prod-wus3-01`): Uses Azure Managed Redis with a different metric namespace (`azure.cache_redisenterprise.*`). Covered separately by the evictions monitor below.

### Client-side monitors

| Monitor | Priority | Threshold | What it catches |
|---------|----------|-----------|-----------------|
| `redis-client-pool-idle-low` | P2 | warn: < 3, crit: < 2 idle connections | Connection pool exhaustion |
| `redis-client-timeouts-any` | P2 | crit: any timeout | First occurrence of a Redis timeout |
| `redis-client-latency-p95-high` | P3 | warn: 500ms, crit: > 1000ms | Elevated Redis latency |
| `redis-evictions-any` | P3 | crit: any eviction (AMR instances) | Key evictions indicating memory pressure |

All thresholds validated against 7 days of live Datadog data (Apr 14–21, 2026) with zero false alerts.

### Monitors considered and removed

- **`redis-client-connection-waits-high`** — `sweagentd.redis.client.connections.waits` is a cumulative lifetime counter exposed as a gauge by go-redis `PoolStats()`. Not suitable for threshold alerting.
- **`redis-client-stale-connections-high`** — Same issue: cumulative counter as gauge. Any static threshold would fire constantly.

## Cosmos DB

**Tracking issue:** [#11503](https://github.com/github/sweagentd/issues/11503)
**Status:** 🔲 TODO

<!-- OTel tracing enabled. Needs: client-side request duration/error metrics, 429 throttle detection, Proxima coverage. -->

## Aqueduct

**Tracking issue:** [#11510](https://github.com/github/sweagentd/issues/11510)
**Status:** 🔲 TODO

<!-- Background job processing. Existing dotcom monitors cover RTT and success/failure rates.
     Needs: job processing duration by type, enqueue failure tracking, Proxima RTT coverage. -->

## CAPI

**Tracking issue:** [#11557](https://github.com/github/sweagentd/issues/11557)
**Status:** 🔲 TODO

## Spokes

**Tracking issue:** [#11586](https://github.com/github/sweagentd/issues/11586)
**Status:** 🔲 TODO

<!-- Git storage via Twirp protobuf RPCs. TLS cert expiry monitoring exists.
     Needs: client-side RPC duration/error metrics, Twirp ClientHooks wrapper, Proxima TLS cert coverage. -->

## Cross-cutting: Network interaction metrics

**Tracking issue:** [#11493](https://github.com/github/sweagentd/issues/11493)
**Status:** 🔲 TODO

<!-- Foundation for global RPC metrics with tags by type (similar to copilot-limiter pattern).
     Many of the above dependency monitors will benefit from this foundation. -->
