# Authnd Strategy

**The north star driving our strategy is to decouple authentication from the github/github monolith.**

Authentication has a significant impact on all our users. It is one of the keystones on which our entire platform is built. Extracting it from the monolith will allow us more latitude to pursue our company-wide performance, scalability, security, and reliability goals.

There are three primary strategic pillars we'll focus on to achieve our goals and demonstrate the value authnd can bring to authentication at GitHub.

## Onboard more services to authnd

This is the strategy we have been pursuing so far, with success. We've already onboarded: Insights, Apps (PATv2), and Swift Registry. We'll continue to seek out new internal customers and demonstrate our value to these services by showing them how they can cut ties with the monolith, something many internal services are already invested in doing. This will also drive us towards including authnd in GHES/GHAE, as more internal services depend on it.

The key challenge in this strategy is finding and convincing teams to onboard. In some cases, these teams have existing, functional authentication strategies. In many cases, those teams are aware of the shortcomings of their current strategies and are excited to adopt authnd. Still, there can be a natural (and totally valid) "if it ain't broke, don't fix it" mentality in those teams. Our job is to convince teams that we can support them in the migration and provide new value on top of their existing authentication strategy.

As we focus more on [Transparent Authentication](#transparent-authentication), this becomes less important as authenticated tokens will be readily available in the request header for downstream services, and onboarding to authnd may not be necessary.

## Build new scenarios on authnd

We are still evolving authentication at GitHub. As we build new features, we will prioritize authnd as the tool we use to build them. We'll use authnd to avoid building up new debt inside the monolith. As a concrete example, we are building the mobile push authentication feature with ~90% of the implementation and 100% of the data storage in authnd. This allows us to justify the value of authnd and avoid creating new migration work for us in the future. It also allows us to immediately progress towards some of our goals (like isolating sensitive credential data), even if we can't fully achieve others (like fully decoupling authn scenarios from mysql1/dotcom uptime).

The key challenge in this approach is that we "look at every problem as a nail" and authnd as "the hammer". Keeping our core goals in mind will help us ensure we avoid "shoehorning" inappropriate scenarios into authnd.

## Put authnd center-stage in major initiatives

We believe authnd can be a star player in some major company-wide initiatives. The authnd service was born during Wall-E out of a goal to support git operations even when the monolith is down. That was quickly scoped out as too much for a single quarter of work, but we are now poised to achieve that goal. We also know that GitAuth uses significant resources, and we're confident that [migrating it to Authnd+Authzd could reduce that cost](#gitauth-experiment-redux) significantly.

We want to pursue other major initiatives, like Transparent Authentication, which would put authnd by the "front-door" and have it resolve credentials before any other service (monolith included) receives them. This would dramatically simplify how services handle authentication and improve our security posture by ensuring that only authnd and our network "front-door" (GLB) handle user credentials. These ideas represent the larger strategy of creating measurable customer value via initiatives in which authnd is a key participant.

The key challenge is that most of these initiatives will require cross-team work. Authentication is a critical factor to achieving many of our company-wide goals but is often not the sole participant. Therefore, we must make convincing arguments for the value of this work to get buy-in from other teams.

## Impact

Authentication is an essential early part of any authenticated request to GitHub, which makes up a significant majority of our requests (approximately 30% of all requests).

Authenticated scenarios have a significant impact on our customers:

- 26,650 authenticated API requests per second
  - Approximately 80% of API requests
- ~10,000 (~6K tokens, ~4K SSH) authenticated Git requests per second
  - Approximately 20% of Git requests

Authentication tables are some of the busiest ones remaining in mysql1. The "authentication_tokens", "oauth_accesses" and "user_sessions" tables are usually the top three tables for I/O write activity in mysql1. The most common authentication scenarios (token & SSH auth for API/Git) [account for ~25% of read queries on mysql1](#appendix-mysql1-impact).

GitAuth [represents a significant COGS impact](#appendix-gitauth-cogs), and a ripe opportunity for cost reduction. The GitAuth/Babeld workload represents approximately 1,400 cores in Kubernetes, and a substantial part of that workload is authentication/authorization.

More stats can be found in [authnd.impact](https://app.datadoghq.com/dashboard/rty-ui5-8sk/authndimpact) on Datadog.

## Goals

We have a few goals for the authnd service:

- Migrate authentication scenarios within dotcom and other services to authnd.
- Remove blockers from decoupling components from the monolith.
- Improve security protections over credential data and reduce handling of credentials
- Make authentication transparent to internal services.
- Scale authentication services independently of gh/gh and mysql1.
- Provide a rich Identity "suite" of tools within GitHub, alongside authzd and other Identity services.

## Requirements

Along with the above goals, we have a few key requirements that we must maintain as we work:

- Parity with GHES/GHAE: We should not require services to handle authentication differently in GHES/GHAE

## Progress Indicators

This section lays out progress indicators that we will use to evaluate our success. We will focus our Initiatives and Epics on making positive progress towards one or more of these indicators.

### Decreased Service Coupling to github/github

A key indicator of success for authnd lies in reducing the coupling of existing and new services to dotcom. Currently, any service that operates on behalf of an authenticated user must call APIs in dotcom, either via Twirp or by residing within the monolith codebase.

Specific indicators here include:

- A decrease in internal monolith Twirp APIs used for authentication.
- More services remain available when dotcom and/or mysql1 are unavailable.
- More services can be built independently of dotcom.

## Improved security protections over credentials

User credentials are one of the most sensitive pieces of information we store. Supply chain attacks and account take-overs have a huge impact on how much trust customers place in GitHub. The security protections we place on this data are key to our compliance requirements. Securing credential data is also one of the most critical things to maintain customer trust.

Specific indicators here include:

- A decrease in credential storage outside authnd.
- Stronger security protections over authentication data (encryption-at-rest), and well-defined pathways for authentication traffic (encrypted-in-transit; as infrastructure allows)
- Increased auditing and monitoring over changes to and handling of credentials.
- Fewer services need to handle credentials directly.

## Reduce the impact of authentication

We must also ensure we are not negatively impacting the customer or developer experience. For example, introducing a new service risks increasing latency and complicating the developer experience, so we should always look at how to reduce that impact.

In addition, we believe authnd can reduce the impact of authentication across the board by providing platform services that keep services away.

Specific indicators here include:

- Continued improvement in latency for authnd services.
- Internal services do not need to consider how to handle credentials.

## Next Steps

Here we lay out a few of the major initiatives we'll continue to push forward and how authnd will support that.

### GitAuth Experiment Redux

We have most of the tools we need to return to the original motivation for the authnd service: Decouple git operations from the monolith. Now that authnd has a stable authentication infrastructure, we could carve off a section of Git functionality and build a full end-to-end that allows Git push/pull operations without being coupled to dotcom.

This will require buy-in from other teams (Authorization, and the teams that own Git infrastructures like babeld, gitauth, and spokesd) and bring direct and measurable customer value. Giving users the ability to push/pull from git even when dotcom is "down" would be a huge win.

The [appendix below](#appendix-gitauth-cogs) indicates we can expect a substantial COGS reduction from migrating GitAuth off the monolith.

## Complete the replication story

We do not support all kinds of tokens in authnd yet. We support all scenarios requested by onboarding services, but there are still a few gaps (mostly around GitHub Apps). We need to complete the replication story and bring full support for all token types to authnd so that we can say without reservation that authnd is ready for all internal authentication workloads.

We also need to consider how to manage replication lag. The replication process isn't free and increases the risk of replication lag. Over time, we may want to shift to adding APIs for dotcom to insert replicated data directly into authnd, and convert the replication process to more of a "backstop".

## Integrate Authnd into GHES/GHAE

GHES/GHAE do not include authnd. As a result, we have primarily focused on onboarding services that do not run on GHES/GHAE. We need to complete the work to properly integrate authnd into GHES/GHAE to be ready to onboard services that run in GHES/GHAE (GitHub Insights, for example). This also becomes necessary as PATv2 moves towards a GHES/GHAE ship.

As we build new services into authnd, like mobile push authentication, we'll also need authnd to be available in GHES/GHAE.

## Transparent Authentication

Authentication should be entirely transparent for internal services. To achieve that, we believe authnd can act as part of a front-end "Gateway" to handle credentials and translate them into internally-trustable tokens. The idea here is that the front-end forwards tokens found in the HTTP Authorization headers over to authnd, which can exchange them for signed short-lived JWT tokens. That gateway would put the authnd-issued token in the request and forward it to the target service (gh/gh, or other services). The target service can then validate the token using a public key and trust the user metadata found within it without looking the token up in a data store or sending it to authnd directly.

![authnd_transparent_auth](https://user-images.githubusercontent.com/7551803/159597549-5489892b-6264-47f1-b0ff-4a7cfa929b0e.png)


This could be achieved incrementally, like most of our projects. We can create the necessary service and run science experiments using dotcom. This enables scenarios that allow us to break individual APIs off of the monolith (like rate limit checking).

Transparent Authentication also helps us move towards a multi-tenant GitHub "universe". The need to detach a "GitHub Identity" from the rest of dotcom, so that it can be relied upon in other environments, has [already been identified](https://github.com/github/github-architecture/discussions/40). Detaching GitHub Identity from dotcom would allow more dotcom systems to be divided into fully-isolated tenants. The GitHub Identity Provider (GH-IdP) provides the central identity across several independent dotcom/GHAE deployments.

Support IdP-issued Tokens Enterprises want to control their own identity. This is a common theme we've seen across our customer bases. Products like GHES, GHAE, and EMUs allow Enterprises to control their identity to a point. Once the user is logged in to the web app, they still have to issue PAT tokens, register OAuth apps and SSH keys manually. On GHEC, users "bless" credentials to bypass SSO authentication checks for operations on those credentials. These are ways in which GitHub requires Enterprises yield back some control over their identity system.

As authnd becomes a central "clearing house" for credentials and resolves all credentials to a standard token format (see Transparent Authentication above), we also gain the ability to diversify the set of credentials we support. Specifically, we can expand to support IdP-issued tokens. For example, an Enterprise on GHEC can establish a trust relationship between their Azure AD tenant and their GitHub.com Enterprise. Then, any user can take an Azure AD-issued token and use it in API requests to GitHub.com (but only for resources owned by that Enterprise, much like how [SSH Certificates](https://docs.github.com/en/organizations/managing-git-access-to-your-organizations-repositories/about-ssh-certificate-authorities) work today). Similarly, in GHES/GHAE, an Enterprise user can take advantage of the existing trust relationship with their own IdP and directly provide IdP tokens to APIs and Git services.

Update: The External Identities team is currently working on/looking at this: <https://github.com/github/external-identities/issues/1348>.

## Migrate more credentials to Authnd

While replication serves us well, it is not our ideal long-term solution. It doesn't directly serve our goals to isolate credential data from mysql1, nor does it substantially reduce the performance impact of authentication scenarios on mysql1. Project Mint gives us a starting point for migrating additional token types to authnd. We also have end-to-end ownership over the SSH Authentication area and could migrate all SSH key storage to authnd (which would help serve the GitAuth Experiment).

Signed Access Tokens are another credential we could look at migrating. We already support verifying them, and generating SAT tokens is fairly simple since we already have the necessary data (user_sessions and a user's token_secret value). However, many usages of SAT tokens require a session ID, and only dotcom receives the session cookie and can decode it to a key. We do have session metadata in authnd's database, so we could add support for looking up a session by a session cookie. However, this would require some redesign of the dotcom session cookie, and would likely need authnd to service a front-end API hosted on github.com, since the cookie is locked to that domain and can't be accessed in JavaScript.

## Risks

### Scope Creep

Scope creep is a significant risk when planning an overhaul of a huge cross-cutting concern like authentication. If we "go dark" to build huge features, we quickly lose relevance and it becomes difficult to justify funding.

We already have a strategy to mitigate this that has been working well. We have always been focused on the fastest reasonable path forward to create an end-to-end scenario. Our replicated data model allowed us to quickly stand up a service, onboard our first major customer (Insights), and respond promptly to requests from other customers (Swift Register, Internal Go Proxy). So the best mitigation here is to focus on finding vertical slices of functionality we can migrate to authnd.

## Scalability Issues

Introducing a new service creates a new scale unit and new scalability risks. Just as there are opportunities to improve scalability, there are new places the system can fail to scale. For example, Authnd will introduce an additional network hop for most, if not all, authentication scenarios in the monolith. Our desire to iterate quickly and work on vertical slices of functionality also introduces the risk that we will take architectural "short-cuts" to keep a high tempo.

Our main mitigation strategy here is to consider Scalability Blockers as much as possible during design. We focus on presenting a limited public surface area to internal services to maintain control over the decisions that impact scalability, even beyond our initial version. We choose initial implementations that may not be perfect but do not restrict our future redesign ability. Rather than finding the ideal scalability solutions, we focus on what will allow us to iterate quickly without blocking future scalability.

## Lack of Adoption

Authnd's success hinges on becoming a central authentication system at GitHub. If we cannot convince services to adopt it, then we cannot achieve the goals listed above.

Part of how we mitigate this risk is by mitigating the other risks above. If our scope is too small, we miss opportunities to onboard services. If our service cannot scale, we let down those services who do take a chance on us.

## Appendix: MySQL1 Impact

It isn't easy to get concrete information about our MySQL impact since query counts don't easily map directly to cost/resource usage metrics. We can get a rough idea of the query impact, though. The details and source metrics for this analysis can be found on the [authnd.impact](https://app.datadoghq.com/dashboard/rty-ui5-8sk/authndimpact?from_ts=1632843249311&to_ts=1632846849311&live=true) dashboard.

1. There are approximately 10 Million queries per minute on mysql1 (reads and writes)
2. There are approximately 677,000 authenticated requests to gitauth per minute
3. There are approximately 1.81 Million authenticated API requests per minute
4. We know that all authenticated gitauth/API requests require at least one query to validate the token/public key.

Given these conditions, we can reasonably estimate that authentication-related queries total about 2.4 Million per minute or about a quarter of all queries on mysql1.

## Appendix: GitAuth COGS

GitAuth consumes [around 1400 cores](https://app.datadoghq.com/dashboard/xeb-yd8-pb2/gitauth-in-k8s?fullscreen_end_ts=1599700086560&fullscreen_paused=true&fullscreen_section=overview&fullscreen_start_ts=1599696486560&fullscreen_widget=922086581826066&tile_focus=5228155174282515&from_ts=1599696486560&to_ts=1599700086560&live=false), to serve [over 30K requests per second](https://app.datadoghq.com/dashboard/xeb-yd8-pb2/gitauth-in-k8s?tile_focus=209208299&from_ts=1599711010771&to_ts=1599714610771&live=false) at peak. We expect to be able to reduce that core count substantially. For context, authnd currently serves [5K requests per second using 8 cores](https://app.datadoghq.com/dashboard/rty-ui5-8sk/authndimpact?from_ts=1632700700291&to_ts=1632787100291&live=true). Authzd serves 5K requests per second using 18 cores. Scaling these linearly up to 30K requests would indicate a number closer to ~150 cores. Of course, these numbers do not extrapolate directly to everything GitAuth does, but it does illustrate potential savings.

In addition, babeld is deployed to several hosts in our datacenter. Babeld does more than just calling gitauth to perform authn/authz. Still, we believe that simplifying gitauth and extracting it from the monolith provides the best opportunity to support an overhaul of Babeld to reduce COGS and security risks (since it is written in C).
