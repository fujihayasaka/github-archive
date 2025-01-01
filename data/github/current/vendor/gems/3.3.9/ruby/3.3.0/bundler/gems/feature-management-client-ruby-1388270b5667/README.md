## Feature Management Client for Ruby

:warning: Clients are currently a work in progress and are not ready for adoption.

Feature Management Client for Ruby is a multi-module repo composing of the clients owned by the [feature-management team](https://github.com/github/feature-management) used for interacting with feature management services.

### Modules

- [vexi](vexi): Client used to answer 'enabled' checks on feature flags used at GitHub
- [vexi_management](vexi_management): Client used to get and perform management information on a feature flag

## Getting Started

To get started with the repo, the following resources are available:

- [Examples](examples) show how to setup and use the clients in your service
- [Adding Modules](docs/adding_modules.md) describes how to create a new module to use in the library
- [Local development](docs/local_development.md) walks through how to build and test the client locally

## FAQ

- **Does this library support management operations e.g. changing the state of feature flags?**: The `vexi` client is available for read-only 'enabled' checks against feature flags in use in a service. The `vexi_management` library, is only meant for local development scenarios, e.g. you need to create / toggle a feature flag as part of a unit or integration test. It is not intended to be used to make production level changes to feature flag data.

## Other Implementations

We maintain implementations of this library for other languages in the following locations:

- [Go](https://github.com/github/feature-management-client-go)
