# Kustomize configuration

This Kustomize configuration is used to generate the kubernetes configuration under `config/kubernetes`.

Build the configuration with:
```
gh kustomize build
```

## Structure

Kustomize creates configuration for environments by combining a base configuration with any applicable overlays.
The union of the directory names under `config/kustomize/base` and `config/kustomize/overlays` is used to determine the deployment targets.
The targets are the names of the environments (stamps) that Heaven will deploy to.
It's not necessary for an environment to have an overlay. For example, `util-jobs` only has a base configuration.

When considering where to make changes it's important to understand the structure.

```
├── base
│   ├── default                     # Base configuration for all environments
│   ├── proxima                     # Base Proxima configuration for all proxima environments
│   └── util-jobs                   # Configuration for the notifyd-transition-job
└── overlays
    ├── production                  # Overlay for the production (dotcom) environment based on `base/default`
    │   ├── kustomization.yaml
    │   └── patches
    ├── proxima                     # Overlay for the proxima environment based on `base/proxima`
    │   ├── kustomization.yaml
    │   └── patches
    ├── prod-ae-01                  # Overlay for the prod-ae-01 environment based on `base/proxima`
    │   ├── kustomization.yaml
    │   └── patches
    ├── prod-sdc-01                 # Overlay for the prod-sdc-01 environment based on `base/proxima`
    │   ├── kustomization.yaml
    │   └── patches
    ┆
    <other environments>
```

Where to make changes:
- For changes that apply to all environments, make them in `base/default`.
- For changes that apply to all Proxima environments, make them in `base/proxima`.
- For changes that apply to a specific environment, make them in the appropriate overlay directory.
  For example, changes that only apply to `prod-ae-01` should be made in `overlays/prod-ae-01`.

For further information about Kustomize see:
- [Kustomize at GitHub](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/kustomize-at-github/)
- [Kustomize Fundamentals](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/kustomize/fundamentals/)

## Environments

The target environments that are output to `config/kubernetes` should map to the environments that are defined in `config/moda/deployment.yaml`.
Proxima environments may not be explicitly defined and instead use an `environment_pattern` to match the stamp name.

### The proxima environment

Note that the `proxima` environment is a special case.
Heaven will use the configuration at `config/kubernetes/proxima` to deploy new Proxima stamps that we don't have explicit configuration for.

Say for example a new stamp called `prod-foo-01` is created and reaches the `Initialized` [stamp lifecycle](https://thehub.github.com/epd/engineering/products-and-services/proxima/stamps/#stamp-lifecycle) state.
Heaven will start to deploy to this stamp using the `proxima` environment kubernetes configuration.
