# Actions Usage Metrics

It's not insights, it's usage metrics!

## What is it?

This repo contains the backend Moda service for Actions Usage Metrics (see the [beta announcement](https://github.blog/changelog/2024-03-28-actions-usage-metrics-public-beta)).

Actions Usage Metrics (AUM) allows GHEC customers to view, filter, and export their Actions usage data aggregated in various ways across different time ranges.

<img src="https://github.com/github/actions-usage-metrics/assets/13670625/cbc7d4f7-33f2-4e46-87e8-a6b198f73eb5" width=750 alt="usage metrics screenshot" />

Actions Usage Metrics is a replacement for the Actions Insights feature which was [decommissioned](https://github.com/github/engineering/discussions/3005) along with the rest of the GitHub Insights platform.

## How does it work?

In a nutshell:

* Data Warehouse ingests `ComputeUsage` Hydro events
* Data Warehouse has Materialized Views (MVs) defined to optimize queries based on job/workflow/etc and time granularities
* Tables and MVs are synced to an Actions-owned Kusto cluster via Kusto follower database feature
* Actions Usage Metrics queries the Actions-owned Kusto cluster containing DWH data
  * The [React frontend](https://github.com/github/github/tree/master/ui/packages/actions-metrics) calls into the [monolith](https://github.com/github/github/tree/master/app/controllers/orgs/actions_metrics), which calls AUM via Twirp.

For more details, you can [read this discussion post](https://github.com/github/c2c-actions/discussions/8424), [watch the demo](https://github.rewatch.com/video/a5yp7ttzakidd3ap-aum-demo-01-19), and [read the ADRs](./docs/adrs/), especially [0479-kusto-data-warehouse-followers.md](./docs/adrs/0479-kusto-data-warehouse-followers.md).

## Feature Status

Current in **Public Beta** for GHEC organizations only.

There are currently no feature flags required to use the feature in its entirety. However, the following feature flags exist for other purposes:

* [actions_usage_metrics_owner_bypass](https://devportal.githubapp.com/feature-flags/actions_usage_metrics_owner_bypass/overview) - **INTERNAL TO GH ONLY**: this must be enabled if the user is not an org admin to allow bypassing the auth check. Note that as an extra safety feature this also checks if the user is a GitHub employee so this does not work outside of GitHub as it is intended to give devs/PM/design access to the page in production without granting admin access

## Got issues?

Please open an issue in <https://github.com/github/actions-fusion> and use label `area:actions-usage-metrics`.  
Or, contact us at `#actions-usage-metrics-dev` (or `#actions-usage-metrics` for general inquiries)

## Builds

[![CI](https://github.com/github/actions-usage-metrics/actions/workflows/ci.yaml/badge.svg)](https://github.com/github/actions-usage-metrics/actions/workflows/ci.yaml)
[![Prebuilds](https://github.com/github/actions-usage-metrics/actions/workflows/codespaces/create_codespaces_prebuilds/badge.svg)](https://github.com/github/actions-usage-metrics/actions/workflows/codespaces/create_codespaces_prebuilds)
[![Publish](https://github.com/github/actions-usage-metrics/actions/workflows/publish.yaml/badge.svg)](https://github.com/github/actions-usage-metrics/actions/workflows/publish.yaml)

## Deploying

There are currently 2 Moda environments. We currently manually deploy to lab before using Merge Queue to deploy to production.

The kubernetes files can be updated by making changes to the overlays and running `gh kustomize build` command

### Lab

We maintain a `lab` environment which allows testing changes against production data before shipping to production.
To deploy to it, use `.deploy <PR> to lab` or `.deploy actions-usage-metrics/<branch> to lab`

The lab environment is also automatically best-effort deployed after production deployments.

### Production

The `production` environment is deployed before merging a PR, via [Heaven Pipelines](https://thehub.github.com/epd/engineering/devops/deployment/onboarding-to-heaven-pipelines) and [Merge Queue](https://thehub.github.com/epd/engineering/devops/deployment/merge-queue).

After you open a PR, you can optionally deploy to `lab` (see above). When you're ready to deploy and merge, just add your PR to the merge queue via the `Merge when ready` button in the PR, or via `.qmtd <PR>`

## Playbooks

Additional docs and playbooks can be found here: <https://github.com/github/ops/tree/master/docs/playbooks/actions/actions-usage-metrics>

## Dev Instructions

Run the service using the following steps:

```sh
script/setup && script/server --dev
```

The `--dev` flag tells `script/server` to watch for file changes and restart the server when changes are detected.
API endpoints can be called via the scripts in `script/`, for example: `script/query-usagesummary <org> <date_range>`.

### Debugging

See the [debugging guide](./docs/debugging/backend-dev.md) to attach a debugger to any AUM backend process (api-server).

### Unit tests

Unit tests can be run by opening the test file and clicking on the green arrow to the left of the tests. You can right-click the arrow to debug and step through the code being tested

### Twirp / Protobuf

#### Making a change

To make changes to our Twirp APIs or protobuf contracts:

1. Make your changes in `proto/`
2. Run `script/protoc`. This consumes the proto files in `proto/` and emits into `lib/twirp/proto` (Golang) and `ruby/lib/proto` (Ruby). It also uses [Buf](https://buf.build/docs/breaking/overview) to detect breaking changes, lint, and format the code.
    * Note: There are multiple levels of breaking changes. "Wire" level breaking changes are almost never allowed as they may break production. "File" level breaking changes are allowed as they don't break the binary wire format used in production, but will require consumers to react (e.g. rename references to a field).
3. Make your application changes in AUM and open a PR! The PR will also validate your twirp/proto changes.

#### Consuming a change in `github/github`

To consume an actions-usage-metrics API change in `github/github` after following the above steps:

1. In a `github/github` codespace, find the `actions-usage-metrics` gem reference in <https://github.com/github/github/blob/master/Gemfile> and follow the `script/vendor-gem` listed above it.
2. Also in the `github/github` codespace, run `bin/tapioca dsl` to update the generated type information.
3. Make your application changes in the monolith and open a PR!

- Note that for testing changes to service you can instead run the command `script/vendor-gem https://github.com/github/actions-usage-metrics.git -r <COMMIT_SHA>`

## Front End

For front end info please see [README here](https://github.com/github/github/blob/master/ui/packages/actions-metrics/README.md)<https://github.com/github/github/blob/master/ui/packages/actions-metrics/README.md>

## Infrastructure

Infrastructure is provisioned with `terraform` and the configuration can be found in the [./config/terraform](./config/terraform/) directory.

To deploy the infrastructure, see [docs/terraform.md](./docs/terraform.md#deploying).

### Resource locks

Azure resources are locked at the resource group level to prevent accidental deletion. Every resource in the resource group inherits the lock. To delete a resource, you will need to remove the lock by commenting out the configuration for the relevant environment in [./config/terraform/locks.tf](./config/terraform/locks.tf). The lock can also be found in the Azure portal under the resource group settings.
