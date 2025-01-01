# Feature Flags

## Table of Contents

- [Details](#details)
- [Feature flag in Code](#feature-flag-in-code)
  - [Vexi CLient](#vexi-client)
  - [Actors](#actors)
  - [Example](#examples)
- [Devportal](#devportal)
  - [Creating your flag in devportal](#creating-your-flag-in-devportal)
  - [Toggling feature flag](#toggling-feature-flag)
- [Dev Environment](#dev-environment)
- [Testing](#testing)
- [Monitoring](#monitoring)

## Details

The Billing Platform uses [vexi-go](https://github.com/github/feature-management-client-go/tree/main/vexi#vexi-go) to feature flag code rollout.

Vexi is the central feature management system that works by publishing flag enablement in dev-portal to hydro topic of the owning service of that flag.

So in Billing Platform vexi-go setup, we [subscribe](https://github.com/github/billing-platform/blob/6046cba0f13489bc202acd6faee0b60484ff50ae/internal/featureflags/featureflags.go#L62) to the `billing-platform` service. This means that billing platform application can only know about changes to a feature flag with `billing-platform` as the owning service.

## Feature flag in Code

To release a code path using a feature flag in billing-platform, wrap the code around flag check on the actor.

### Vexi Client

An instance of vexi-go client should exist in the engines and handlers via "EngineParams" as `flagger`.

### Actors

Billing Platform is centered around `Customer` and not necessarily the entity types (Business, Organization, User). As a result, the actor for a feature flag will be a "Customer" actor.

Use `models.CustomerVexiActor("1234")` ([defined here](https://github.com/github/billing-platform/blob/6046cba0f13489bc202acd6faee0b60484ff50ae/lib/models/models.go#L89C1-L91C2)) as the actor of the flag check in order to rollout a feature/code path to a specific customer.

### Examples

Usage example:

```go
func main() {
  ctx := context.Background()
  cfg, _ := config.Load()
  logger := cfg.ConfigureLogger(telem.Logger)
  statter := cfg.StatsClient()
  statter.Run()
  defer statter.Stop()

	flagger, err := featureflags.NewClient(ctx, cfg, logger, statter)
	if err != nil {
		logger.Error("failed to create feature flag client", kvp.String("error", err.Error()))
		_ = errorReporter.Report(ctx, err, nil)
	}

  if flagger.IsEnabledWithDefaultValue(ctx, "sample_feature_flag", false, models.CustomerVexiActor("1234")) {
    // do something when flag enabled
  } else {
    // do something when flag disabled
  }
}
```

Example in an engine

```go
func (u *UsageEngine) GetLineItems() error {
  if u.flagger.IsEnabledWithDefaultValue(ctx, "sample_feature_flag", false, models.CustomerVexiActor("1234")) {
    // do something when flag enabled
  } else {
    // do something when flag disabled
  }
}
```

Example in an handler

```go
func (h *UsageHandler) applyConfiguredDiscount(ctx context.Context) error {
  if h.flagger.IsEnabledWithDefaultValue(ctx, "sample_feature_flag", false, models.CustomerVexiActor("1234")) {
    // do something when flag enabled
  } else {
    // do something when flag disabled
  }
}
```

## Devportal

### Creating your flag in devportal

In order to toggle a feature flag in production, you'd need to create the flag in [dev portal](https://devportal.githubapp.com/feature-flags).

> [!IMPORTANT]
> Ensure to set the "Owning Service" for your flag to `billing-platform` as we only listen for feature flag changes for that service. If you already by mistake create the flag under a different service, you'll need to create a differerent flag (with new name) as you can't update the "Owning Service" in devportal.

### Toggling Feature Flag

In [dev portal](https://devportal.githubapp.com/feature-flags), to enable a feature flag for a specific actor, use the Flipper IDs field. Add `Customer:1234` in the "Flapper IDs" field to enable the flag for Customer with ID "1234".

You can also fully enable the flag in each stamp to enable for all Customers

## Dev Environment

In development environment, use the [`fm-lite`](https://github.com/github/feature-management-lite) CLI to manage flag enablements

```bash
fm feature enable --create -n "MyFeatureFlag" #create and enable "MyFeatureFlag" globally
fm feature actor add -n "MyFeatureFlag" -i "Customer:111 Customer:123 Actor:10000" # add listed actors with IDs to the feature flag
```

You can read more about the CLI once installed with fm --help

## Testing

We have a helper `NewFeatureFlagClient` that returns a vexi client and "fake adapter". Pass the client as the `flagger` attribute of the engine being tested. Then use the returned adapter to tweak the enablement state.

Example

```go
vexiClient, vexiAdapter := helpers.NewFeatureFlagClient(context.Background(), t, false)

engineParams := &EngineParams{
  db:             mockDB,
  cfg:            cfg,
  aqueductClient: aqueductClient,
  statter:        stats,
  flagger:        vexiClient,
}

pricingEngine := NewPricingEngineWithQuerier(engineParams, pricingQuerier, gatewayPricingQuerier)

...

// test code path of flag not enabled

vexiAdapter.AddFeatureFlag(featureName, false) // create flag but disabled globally
vexiAdapter.AddActors(featureName, []string{"Customer:111", "Customer:123"})

// test code path of flag enabled
```

## Monitoring

Each feature flag ([example](https://devportal.githubapp.com/feature-flags/accessibility_settings_forms/overview)) has a DataDog link to see "Feature Flag Results" on the right pane.
