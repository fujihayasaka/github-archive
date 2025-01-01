# Image Management Service

The Hosted Compute **I**mage **M**anagement **S**ervice (or IMS) is a service responsible for image promotion and image management for both Standard and Larger Runners in the 4-9s architecture.

This service is owned by the [Compute Turbine team](https://github.com/github/actions-compute-turbine).

Slack channel: [#hosted-compute-ims](https://github.slack.com/archives/C05K4MVQDMW)

## Quick Start 🚀

Codespaces is the preferred environment for IMS development. See [Development](./docs/development.md) for more information on development process.

Start image management service:

```console
script/server
```

## Links and Resources

- Service overview
    - [Design](./docs/design.md)
    - [Environments](./docs/environments.md)
    - [Packages overview](./docs/packages-overview.md)
    - [Jobs overview](./docs/jobs.md)
    - [Brownbags and meetings](./docs/meetings.md)
- Development process
    - [Development](./docs/development.md)
    - [Database](./docs/database.md)
    - [Feature Flags](./docs/feature-flags.md)
    - [Vault](./docs/vault.md)
    - [ADRs](./docs/adrs/README.md)
    - [Implementation plan](./docs/implementation-plan.md)
- Monitoring, Telemetry, Logs
    - [📡 Telemetry overview](./docs/telemetry.md)
    - [☸️ Moda](https://devportal.githubapp.com/apps/hosted-compute-ims)
    - [📈 Dashboard](https://app.datadoghq.com/dashboard/vwb-6j5-4ry)
    - [🪵 Splunk](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22hosted_compute_ims%22%20deployment.environment%3Dproduction)
    - [🪲 Sentry](https://github.sentry.io/issues/?environment=production&project=4506904886116352&statsPeriod=24h)
