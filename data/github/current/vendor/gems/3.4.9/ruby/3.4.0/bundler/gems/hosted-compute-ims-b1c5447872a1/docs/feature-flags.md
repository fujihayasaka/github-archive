# Feature Flags

The current implementation of feature flags in IMS uses [Monolith Feature Flags](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/) and [Twirp Features API](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp) client to retrieve the feature flags state.

## Adding a new feature flag

1. Go to [DevPortal](https://devportal.githubapp.com/feature-flags) and create a new feature flag
    - Feature flag name **must** start with `ims_*` prefix
    - Owning service **must** be set to `hosted-compute-ims`

If flag is intended to enable image for customers:

2. Go to [IMS stafftools](https://admin.github.com/stafftools/hosted_compute_ims_admin) and create or edit image definition
3. Set `Enabled` field to `Feature Flag` and specify feature flag name. Save image definition

If flag is intended to be used in IMS code:

2. Define a new `FeatureFlag` in [featureflags/constants.go](../internal/featureflags/constants.go), to make it re-usable and easier to track down. These flags need to be unique across all of GitHub
3. Use feature flags singleton client  to check the value of the feature flag in your code, you can check either globally or per owner:

```golang
// check feature flag state globally
flagEnabled := featureflags.IsFeatureFlagEnabledGlobally(ctx, featureflags.FeatureFlag_MyNewFeature)

// check feature flag state for owner
ownerId := "O_kgDOAf4wIg"
flagEnabled := featureflags.IsFeatureFlagEnabledForOwner(ctx, featureflags.FeatureFlag_MyNewFeature, ownerId)
```

## Enabling or disabling feature flag globally

1. Go to feature flag page on [DevPortal](https://devportal.githubapp.com/feature-flags)
2. Go to `dotcom` stamp
3. Switch to `Danger zone` tab
4. Use `Stamp enablement` -> `Enable` / `Disable` buttons

## Enabling or disabling feature flag per owner

1. Go to feature flag page on [DevPortal](https://devportal.githubapp.com/feature-flags)
2. Go to `dotcom` stamp
3. Click `Manage actors` -> `Add actors`
    - Use `Organizations` field to enable FF for organizations
    - Use `Enterprise` field to enable FF for enterprise

> [!WARNING]  
> Feature Flag state is not inherited from enterprise to organizations (aka enabling FF for billing owner). It means FF should be enabled for enterprise and every organization in enterprise separately.

## Feature flags in local environment

If you develop in dotcom codespace and dotcom is running, IMS will consume feature flags from dotcom environment.  
Use dotcom UI or `cd $GITHUB_PATH && bin/toggle-feature-flag enable myflag` to manage feature flags.

Otherwise, If you develop in IMS codespace or dotcom is not running, IMS will fallback to local feature flags store for local environment.  
If you need to enable some feature flags in local feature flag store, use [config/kustomize/devoverlays/feature-flags.yml](../config/kustomize/devoverlays/feature-flags.yml).

The file structure is pretty simple:
```yml
enabledGlobally:
  - ims_e2e_test_feature_globally_enabled
enabledPerOwner:
  - flag: ims_e2e_test_feature_enabled_per_owner
    owner: O_kgDOAf4wIg
```
