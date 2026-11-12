We're on proxima now!

That means that for future releases, you will be simultaneously shipping for proxima as well as dotcom, and you need to make sure that your new feature works on proxima as part of its broader release.

---

### Key Differences for `sweagentd` on Proxima
- **Tenant context:** All service consumption happens through a tenant (via URL or header).  
- **Configuration resolution:** `GetConfigurationForRepository` resolves tenant info when Hydro messages don’t include it.  
- **Privileged app sync:** Our app is [synced to Proxima environments](https://thehub.github.com/epd/engineering/products-and-services/dotcom/apps/proxima/how-to-synchronize-apps-on-proxima/). Docs clarify which fields match vs. differ across environments.

### How to Know if a Feature Needs Proxima Consideration
- **New dependencies:** If adding cross-service dependencies in GitHub, check whether the service is supported on Proxima and if it requires special access.  
- **Hydro events:**  
  - Events from **dotcom** → include tenant headers by default.  
  - Events from **other sources** → may lack tenant headers (often easy to add).  
- **Security/GitHub Apps:** If adding new security requirements or novel GitHub App usage, confirm how these map to Proxima.

### How do I test in proxima?
>[!Caution] 
> ONLY directly deploy to `test-cnc-01` in proxima. Treat this environment like a staging environment. DO NOT directly deploy to other proxima environments.
* The same way you do for normal production! Enable a feature flag targeting a test tenant (or our organization on the test tenant) for a specific stamp.
* Each proxima stamp has a `coding-agent-test/test-cca` on the default test tenant for the stamp.
* All user assignment is manual in proxima, so you may want to target an environment you know works, but our team channel can help you locate someone who can add you to a different tenant or stamp.
* Check [How can I debug proxima](#how-can-i-debug-proxima) for things like Splunk, Sentry, etc. links that are stamp specific.
* You don't need to test each production stamp individually, but it is advised if you are doing something that has environment specific implications (like adding a new secret or connection string).

### What parts of our app are most impacted by Proxima support?

* **Inbound requests have to carry tenant affinity**
   * For hydro events, this means we need the hydro events to have [tenant headers](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/events/hydro/dispatcher.go#L103).  
   * For inbound API requests, participating in GitHub's tenant headers will automatically get tenant [loaded into our context](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/cmd/http/main.go#L440).
   * If you need to get tenant from our context, _make sure_ to use the requestctx methods, which will check all the places tenant context could be stored.
* **Outbound requests often have to be tenant aware**  
   * We use placeholder replacement that you can mostly link back to [ReplaceTenantPlaceholder](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/proxima/proxima.go#L14) .
   * We make sure to [add tenant headers](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/githubtwirp/client.go#L147) at different places where we make outbound requests, but some services bake tenant information into the URL.
* **Some services like Experimentation are not implemented in Proxima**  
   * [As an example](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/experiments/proxima.go#L12), we see a stubbed out implementation of the experimentation client that is used in proxima environments.
* **Our configuration stores the Proxima environment information for the actively running application**  
   * We expose both an [enum level classification](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/config/config.go#L365) of environment (useful when doing "for all proxima environments" type logic) and the EnvironmentName itself (generally more for logging).
* **Actor login is deprecated, Display Login is what Proxima needs**
   * Namespacing logins is described in [detail here](https://github.com/github/proxima/blob/main/docs/tenancy/namespacing.md).
   * There are a lot of caveats to this, but in general, using public github apis with the value from `login` for actors will cause problems.
   * As a result, we use internal APIs (like most other github services), which allow us to use Login in place of DisplayLogin.
   * If the need arises to use Login in a place that doesn't go through the monolith's normal namespaced data rules, you **must** use display login. We do this most in places where we might be saving the Login to a user visible string outside of the monolith.
   * We have a handy helper for [resolving display login](https://github.com/github/sweagentd/blob/ca046cdd8d5017676173dd293f58264f7c411996/internal/githubtwirp/helpers.go#L153). Ideally, you shouldn't need to use this, but not all parts of GitHub have "caught up" to exposing DisplayLogin wherever they might only be surfacing Login.
* **We use different OAUTH application IDs per stamp**
   * We have to configure both [CAPI](https://github.com/github/copilot-api/blob/0b53908623b7f11c7e3bf6ebe6ae5d13579e43dc/config/kubernetes/prod-weu-01/deployments/copilot-api.yaml#L91) and [our own environment](https://github.com/github/sweagentd/blob/8887aba935b72cf6df190aff16bd3ca42c82a503/config/moda/configuration/prod-weu-01/env.yaml#L7) with the OAUTH app information that is stamp specific. 
* **Because CAPI is a proxy to sweagentd, CAPI has to forward its own tenant information**
   * CAPI is always addressed with a tenant in the host name (not necessarily as a tenant header).
   * The reverse proxy implementation will [fetch the active tenant and convert it into a tenant header](https://github.com/github/copilot-api/blob/main/pkg/agent/agentproxy/agentproxy.go#L104) to send to sweagentd.

---

### References?

#### Video references about Proxima?
* [Proxima 101](https://www.loom.com/share/d562247286754d21874b41a41142da93)
* [Proxima Deep Dive](https://www.loom.com/share/82643fca7aed4eb882e6bec80925a6c7)

#### How can I debug proxima?
* Use [the proxima ops playbook](https://github.com/github/ops/blob/1e3d4d7f2918f185c441b47563a5714a332a8b96/docs/playbooks/proxima.md)

#### How does proxima really work?
* Check out [the engineering design](https://thehub.github.com/epd/engineering/products-and-services/proxima/proxima-engineering-design/)
* General [proxima observability design information](https://thehub.github.com/epd/engineering/products-and-services/proxima/observability/)

#### How do I test proxima specific features in the monolith?
* Check out the [multitenant test guide](https://thehub.github.com/epd/engineering/products-and-services/proxima/multi-tenant-mode-test-guide/)

#### How do I test proxima specific features in sweagentd? 
* We use our configuration's environment value to determine if we are in proxima in places where we don't expect to have a tenant, but `requestctx.Tenant()` is good enough, too!

#### How does CAPI do proxima?
While CAPI is not _data resident_ it _is_ on proxima!
* Check out the [CAPI proxima documentation](https://github.com/github/copilot/blob/main/docs/copilot-api-service/proxima.md)
