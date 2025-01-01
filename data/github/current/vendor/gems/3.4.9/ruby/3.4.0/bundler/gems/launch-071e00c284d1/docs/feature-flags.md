# Feature Flags

Feature flags are the best way to gradually roll out changes safely, decoupling code changes from the deployment of those changes.

This document intends to cover the use of feature flags within Launch.
For a full overview of feature flags, see [The Hub: Feature Flags](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/)
and [The Hub: Feature Flags Overview](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/overview/).
Some of this documentation is specific to feature flags in the Monolith, but the general information about rollouts still applies.

## How to use a feature flag

Feature flag state is stored in the Monolith. Launch does not maintain its own state or set of feature flags.
Launch feature flags are managed in the same [DevPortal](https://devportal.githubapp.com/feature-flags/) as other feature flags; there is no "native" feature flagging within Launch itself.
This means that any feature flag check requires a call to the Monolith, through Twirp or GraphQL.

### Twirp features

Launch can check a feature flag using a [Monolith Twirp](https://github.com/github/monolith-twirp-features) API, which the Launch Twirp client exposes through:
* `IsFeatureEnabledGlobally`
* `IsFeatureEnabledForActor`
* `IsFeatureEnabledForActors`
* `IsFeatureEnabledForRepoOrOwners`
* `IsFeatureEnabledForRepository`

On top of calling the underlying Monolith Twirp Feature APIs, Launch will map to the correct actor ID
format and cache the response.

> [!NOTE]
> An "actor" here refers to a [`FlipperActor`](https://github.com/github/github/blob/master/lib/github/flipper_actor.rb),
> which is any entity that [includes the flipper actor module](https://github.com/search?q=repo%3Agithub%2Fgithub+include+GitHub%3A%3AFlipperActor&type=code). Within the context of Launch,
> this is typically a user, organization, repository, or enterprise account. This is different from
> how we use the term actor throughout Launch to refer to the user/entity responsible for 
> triggering an event.

Excluding `IsFeatureEnabledForActors`, feature flags are cached for 30 seconds ([`isFeatureEnabledForActorCacheExpires`](https://github.com/search?q=repo%3Agithub%2Flaunch%20isFeatureEnabledForActorCacheExpires&type=code).
`IsFeatureEnabledForRepoOrOwners` will additionally look up the owners for a repository and cache that response for 1 hour.
To optimize the cache hit rate, the actor and repository feature flag checks all check if a feature flag is globally
enabled first before checking a specific actor.

These functions do not return errors, logging them instead and returning `false`. This means that flags can
be fully enabled and still appear as disabled to Launch if there are errors reaching the Monolith.

#### Checking a feature flag via Twirp

For code that already access to a `ghtwirp.Client`, checking a feature flag is straight-forward:

```go
if ghTwirpClient.IsFeatureEnabledForActor(ctx, github.MyFeatureFlag, repoGlobalID) {
  // Do something with the flag enabled
}
```

If a `ghtwirp.Client` is not available, then you'll need to plumb through the Twirp client from the
`application.go` or `main.go` of the service.

```go
// main.go
myService, err := my.NewService(
  cfg,
  githubTwirpClient,
)
```

```go
package my

import (
  "context"

  "github.com/github/go/config"

  "github.com/github/launch/clients/ghtwirp"
  "github.com/github/launch/types"
)

// my/service.go
func NewService(
  cfg Config,
  githubTwirpClient ghtwirp.Client,
) (*service, error) {
  // Pass Twirp client to where it's needed
}
```

If you only need the Twirp client for checking the feature flag, prefer passing in a function to
abstract away the implementation:

```go
// main.go
myService, err := my.NewService(
  cfg,
  githubTwirpClient.IsFeatureEnabledForActor,
)
```

```go
package my

import (
  "context"

  "github.com/github/go/config"

  "github.com/github/launch/types"
)

// my/service.go
func NewService(
  cfg Config,
  actorFFChecker func(context.Context, string, types.GlobalID) bool,
) (*service, error) {
  // Pass feature flag function to where it's needed
}
```

This makes testing easier and avoids code taking an unnecessary dependency on the `ghtwirp` package.

### GraphQL features

The GraphQL API can be used to fetch feature flag state through `isFeatureEnabled`:
```gql
query DataForWorkflowInvocation($repo: ID!) {
  repository:node(id: $repo) {
    ... on Repository {
      launchLabEnabled:isFeatureEnabled(name:"launch_lab")
    }
  }
}
```

This can be useful when adding feature flags to flows that already call the Monolith through GraphQL,
such as webhook event processing in Launch Worker. The most common place to add these feature flags is
in [`queryDataForWorkflowInvocation`](https://github.com/github/launch/blob/22bb1b7805f62b01cac3d2906c986d1b6518deea/clients/github/getworkflowinvocationdata.go#L40),
but other GraphQL queries can be adjusted as long as there's a valid actor being queried.

For an example, see https://github.com/github/launch/pull/7075.
While this does avoid an extra Twirp API call, it can be a bit more plumbing/friction and isn't as flexible as
a Twirp API call. For long-lived feature flags, prefer using an existing GraphQL query. For short-lived
feature flags, the extra Twirp API call likely won't matter.

## When not to use a feature flag

There are some scenarios where checking a feature flag is not practical or possible. When not using a feature flag,
ensure changes are tested thoroughly. The Lab & Proxima Staffship environments are great ways to test changes in a
production environment.

To learn how to make use of these environments for your testing, see our [deploying](./deploying.md) docs.

### High-traffic code that's called frequently

Checking a feature flag can require an external call to Redis and the Monolith if there's
no cached feature flag (some caching is in-memory). Code that's called very frequently should avoid
introducing additional external network calls, so feature flags are likely not a good fit. For example,
we shouldn't check a feature flag every time we log.

If you're making changes to these areas and want to roll them out safely, consider using a configuration
variable. Configuration variables can be checked frequently and allow rolling out changes per-environment
and Launch service.

### Updating a dependency

Depending on the dependency, it might not be practical to have multiple versions of the module
side-by-side. Read through release notes for any breaking changes and utilize our testing environments
to validate these sort of changes.

### Application startup or configuration changes

Checking a feature flag during application startup can be done after the GitHub Twirp client is
initialized, but this wouldn't allow us to rollback changes without redeploying Launch. Similar to
"High-traffic code that's called frequently", it's typically easier to utilize configuration variables
to roll out these changes across services and environments.

### Changing code already behind a feature flag

When making changes to code that's already behind a feature flag, you may not need another feature flag.
If the feature is already fully enabled, ensure it's safe to disable before re-using it. For example
if the feature is fully enabled and customers are dependent on it, you risk breaking customers by disabling it.

### Non-production code changes

If no production code is changing, a feature flag isn't needed. This includes renaming variables
(excluding `struct`s that are serialized directly like `Invocation`), updating comments, updating tests,
or adding documentation.

Outside of these scenarios, if you're making code changes then you should use your best judgement to
determine if your changes warrant a safer rollout with a feature flag.

## Best Practices

### Define a string constant for every feature flag

Every feature flag should be defined in a `const`. This makes it easy to see which flags Launch
depends on and serves as a place to document the function of the feature flag. Most feature flags
are defined in [`featureflags.go`](../clients/github/featureflags.go) in `package github`. Code that
can't depend on that package should define the feature flag within their package directly, such as
`clients/github/tokens/featureflags.go`.

### Avoid dark-shipping

Dark-shipping is the process of enabling a feature flag for a percentage of calls, regardless of the actor.
This is useful for flags in Dotcom that don't have an actor passed in, but doesn't work well in Launch.
Since feature flags are cached for 30 seconds, the percentage of calls enabled won't actually match reality.
Additionally, Launch checking if the flag is globally enabled first before the actor will skew the number of calls.

Shipping flags by a percentage of actors provides a more consistent experience and behavior.

### Ensure flags can be disabled

A feature flag is only useful if it's safe to disable to mitigate impact. When planning a rollout,
ensure that it's safe to disable any feature flags without causing new issues. This might mean checking
multiple dependent feature flags at the same time or removing fully enabled feature flags first.

### Ensure every feature flag has an issue tracking cleanup

Every feature flag should be tracked in an issue somewhere. This could be done in the issue tracking
the work that added the feature flag or in a separate [feature flag rollout issue](https://github.com/github/actions-launch/blob/main/.github/ISSUE_TEMPLATE/feature-flag-rollout.md).

### Only use `IsFeatureEnabledForRepoOrOwners` when necessary

`IsFeatureEnabledForRepoOrOwners` can be useful when changes need to be rolled out to multiple organizations
for internal testing or customer feedback. `IsFeatureEnabledForRepoOrOwners` is two to three feature flag checks on the
repository, organization/user, and an enterprise account if it exists. For this reason, it's not
as useful when rolling out a flag on a percentage of actors as the resulting "enabled" percentage
will skew higher (see https://github.com/github/c2c-actions-experience/issues/5945).

For most changes, checking a feature flag on a repository is sufficient
and still allows for [Staff-shipping](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/overview/#shipping-to-staff).

### Only use `IsFeatureEnabledGlobally` within context which don't have an actor

Due to the issues described in [Avoid dark-shipping](#avoid-dark-shipping), there isn't a great
way to gradually roll out a globally enabled feature flag. `IsFeatureEnabledGlobally` is typically
only used as a "last resort" when there's not a relevant actor in the context.
