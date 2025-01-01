# Feature Flags

The current implementation of feature flags in IMS uses [Monolith Feature Flags](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/). 

We use the [Vexi](https://github.com/github/feature-management-client-go/tree/main/vexi) client along with the [Twirp Features API](https://thehub.github.com/epd/engineering/products-and-services/dotcom/features/feature-flags/twirp) client to retrieve the feature flags state.

[This proposal has more details](https://github.com/github/hosted-compute-ims/pull/935) on why we have both twirp and vexi. The aim is to migrate fully to Vexi once proxima IMS proxy is implemented.

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
actor := models.NewActorFromGlobalIdAndStamp(imageDefinition.OwnerId, "") // or from API
flagEnabled := featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag_MyNewFeature, actor)

// check feature flag state for image definition
flagEnabled := featureflags.IsFeatureFlagEnabledForActor(ctx, featureflags.FeatureFlag_MyNewFeature, imageDefinition)
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

## Enabling or disabling feature flag per image definition

1. Go to [IMS stafftools](https://admin.github.com/stafftools/hosted_compute_ims_admin) and take production ID of image definition
2. Go to feature flag page on [DevPortal](https://devportal.githubapp.com/feature-flags)
3. Go to `dotcom` stamp
4. Click `Manage actors` -> `Add actors`
5. Set `Flipper IDs` property to `ImageDefinition:<image_definition_id>` (Ex: `ImageDefinition:1`)

## Feature flags in local environment

If you need to enable some feature flags in local feature flag store, use [config/kustomize/devoverlays/feature-flags.yml](../config/kustomize/devoverlays/feature-flags.yml).

The file structure is pretty simple:
```yml
enabledGlobally:
  - ims_e2e_test_feature_globally_enabled
enabledPerActor:
  - flag: ims_e2e_test_feature_enabled_per_owner
    actor: "Organization:33435682" # global id: O_kgDOAf4wIg
```

In IMS and Dotcom codespaces these flags will be set as part of the codespace (via `script/setup`).

If you want to change FFs while developing, edit the file then run `make feature-flags-update`. This will update the state of the flags. 

Behind the scenes this uses [`feature-management-lite` cli `fm`](https://github.com/github/feature-management-lite), you can also use fm to manually make changes but these will be
overwritten when `make feature-flags-update` is run. 
