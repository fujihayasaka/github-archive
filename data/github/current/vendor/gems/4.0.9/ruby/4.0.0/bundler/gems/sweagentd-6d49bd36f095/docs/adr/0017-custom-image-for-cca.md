# Run CCA Workflows on a Custom Image

Status: accepted

Deciders: @bogdanap @cschleiden @srt32 

Related issue: https://github.com/github/sweagentd/issues/10179

## Context

CCA agent startup involves several sequential phases: job creation and API routing, GitHub Actions workflow setup (downloading and extracting the runtime, installing Node.js, starting MCP servers, generating firewall certificates), and finally agent loop initialization. On the default `ubuntu-latest` hosted runner, the workflow setup phase alone takes ~20s at p50, and the full request-to-running time is ~40s at p50.

A significant portion of that time is spent on work that is identical across every job: downloading and extracting the runtime tarball, running `setup.sh` to install Node.js, pre-caching the Playwright MCP server package, and generating mkcert CA certificates for the firewall. These steps are deterministic for a given runtime version and don't depend on the user's repository or task.

### Current status

On `ubuntu-latest`, the workflow setup phase (`launched_to_started`) averages ~21s at p50, and end-to-end startup (`request_to_running`) averages ~40s at p50. The main time sinks in the workflow are:

- **Runtime download and extraction** (~4s): Downloading the runtime tarball from codeload and extracting it.
- **Playwright MCP pre-caching** (~3s): Running `npm cache add` to pre-cache the Playwright MCP server package so it's available when the agent needs it.
- **Firewall certificate generation** (~5s): Running `mkcert` to generate a CA certificate for the eBPF firewall's HTTPS interception.

### Requirements

- The custom image must be kept in sync with the runtime version deployed by sweagentd. A version mismatch must fall back to the standard download path.
- The image build and publication process must be automated and tied to runtime deployments.
- The solution must not break existing functionality for self-hosted runners, Windows runners, or users with custom setup steps.

## Alternatives considered

- **Optimize the existing workflow steps without a custom image**: We could parallelize more steps or use faster download mechanisms. However, the fundamental issue is that we're repeating identical work on every job. No amount of optimization within the workflow can eliminate the download and extraction time entirely.
- **Cache a Docker overlay layer via [Actions persistent storage](https://github.com/github/actions-persistent-storage-poc/tree/main)**: We explored caching the runtime and dependencies as a Docker overlay layer that could be restored at job start. However, downloading the cached layer took a similar amount of time as downloading the runtime directly, negating the benefit.

## Decision

We use a custom pre-seeded VM image for CCA jobs on hosted runners. The image is built on top of the standard `ubuntu-latest` base and includes:

1. **The CCA runtime** pre-installed at `/opt/copilot-runtime/copilot-developer-action-main/`, with a `version` file containing the runtime SHA for version verification.
2. **Node.js** pre-installed at `/opt/copilot-runtime/ghcca-node/` via the runtime's `setup.sh`.
3. **Playwright MCP server** pre-installed globally and configured as a systemd service (`playwright-mcp.service`) that starts automatically on boot, listening on port 3100.
4. **mkcert CA certificate generation** configured as a boot-time systemd service (`copilot-mkcert-ca.service`) so that the firewall CA is ready before the workflow starts.

The workflow detects the pre-installed runtime by checking for the presence of `/opt/copilot-runtime/copilot-developer-action-main/` and verifying the version file matches the expected runtime SHA. On a match, it symlinks the pre-installed paths and skips the download, extraction, and setup steps. On a mismatch (e.g., during a deployment rollout), it falls back to the standard download path transparently.

The image is built by the `build-custom-copilot-image.yml` workflow, which is triggered automatically when the `runtime` submodule is updated on `main`, or manually via `workflow_dispatch`. The Actions infrastructure validates the image before publishing it to the custom runner pool.

Jobs running on the custom image use the runner label `ubuntu-cca-77785908-7ef3-498a-9ae0-bbebb95125d3`, which is assigned by the sweagentd service when launching jobs.

### Observed performance improvement

Production metrics comparing the custom image against `ubuntu-latest` over the past days ([Datadog notebook](https://app.datadoghq.com/notebook/14175235/bogdana-cca-custom-image)) show:

| Metric (p50) | `ubuntu-latest` | Custom image | Improvement |
|---|---|---|---|
| Request to running (end-to-end) | ~43s | ~34s | **~9s** |
| Launched to started (workflow setup) | ~16s | ~10s | **~6s** |
| Started to running (agent loop init) | ~22s | ~19s | **~3s** |

The bulk of the improvement comes from the workflow setup phase, where the runtime download, MCP pre-caching, and firewall cert generation are eliminated.

## Implications

**What becomes easier:**
- Startup latency is reduced by ~8–10s at p50, directly improving user experience for every CCA job on hosted runners.
- The workflow becomes simpler when running on the custom image—fewer steps, fewer failure modes during setup.
- Boot-time systemd services (Playwright MCP, mkcert CA) can be further extended to pre-warm other components in the future.

**What becomes harder:**
- We now have a custom image to maintain. The image must be rebuilt and validated whenever the runtime version changes.
- There is a deployment coordination concern: when a new runtime version is deployed, there is a window where the image version lags behind. The version-check fallback handles this gracefully, but jobs during that window won't get the full benefits of the custom image.
- Debugging startup issues becomes slightly more complex, as there are now two code paths (pre-installed vs. downloaded) that need to be considered.

**Operational considerations:**
- Deploying a new version of the custom image currently takes ~3 hours end-to-end. We don't have deep visibility into the Actions-side deployment pipeline, which is managed by the Actions team.
- To mitigate risk, we added a long-lived feature flag (`copilot_swe_agent_disable_custom_image`) that allows us to immediately disable usage of the custom image for specific users, repositories, or organizations without waiting for an image redeploy. When this flag is enabled, jobs fall back to `ubuntu-latest` and the standard download path.

**Risks:**
- If the image build pipeline fails or is delayed, jobs fall back to the download path with no user impact, but we lose the latency benefit.
- The custom runner pool is managed by the Actions team. Any changes to the hosted compute infrastructure could affect image availability.
