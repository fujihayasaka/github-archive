# Feature Flags

> [!NOTE]
> We are currenly evaluating the use of Feature Flags (using the Features Twirp API) in Billing Platform. If you are considering adding a feature flag, please start a discussion in #billing-platform first. See this [issue](https://github.com/github/gitcoin/issues/11371) for more details.

## Table of Contents

- [Details](#details)
  - [Feature flags in Billing Platform](#feature-flags-in-billing-platform)

## Details

### Feature flags in Billing Platform

The Billing Platform uses the same [feature flags](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/) used everywhere else in GitHub, connecting to the monolith feature flags using [Twirp](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp/).

The `FlagChecker` interface in [`lib/feature_flags.go`](https://github.com/github/billing-platform/blob/main/lib/feature_flags/feature_flags.go) provides access to the feature flags service exposed by the Monolith.

If possible, it is best to initialize the Feature Flag Client in a `main()` function and pass it to any code that may make use of it (to limit the number of Twirp connections that need to be made in order to use feature flags).

Usage example:

```go
func main() {
  cfg, _ := config.Load()
  logger := logger := cfg.ConfigureLogger(telem.Logger)
  statter := cfg.StatsClient()
  statter.Run()
  defer statter.Stop()
  flagger := cfg.NewFeatureFlagClient(logger, statter)
  stuffDoer = LetsDoSomeStuff(flagger)
}

func (t *Thing)LetsDoSomeStuff(flagger featureFlags.FlagChecker) {
  featureFlagName := "do_some_stuff"
  shouldWeDoStuff, err := flagger.CheckGlobalFeature(ctx, featureFlagName)

  if err == nil && shouldWeDoStuff {
    // do some stuff here
  }
}
```
