# How to Ingest Actions Usage

This document explains how to setup a codespace to ingest Actions usage.

## Table of Contents

- [Terminology](#terminology)
- [Details](#details)
  - [How to setup a codespace to ingest Actions usage](#how-to-setup-a-codespace-to-ingest-actions-usage)
  - [How to produce Actions usage events](#how-to-produce-actions-usage-events)
- [FAQ](#faq)
- [References](#references)

## Terminology

- **Ingesting usage**: Refers to sending usage from a partner feature to the billing platform through hydro to be processed by the billing platform.

## Details

### How to setup a codespace to ingest Actions usage

1. Create a new dotcom codespace and select the [Actions Development dev container configuration](https://github.com/codespaces/new?hide_repo_select=true&ref=master&repo=3&skip_quickstart=true&machine=xLargePremiumLinux&devcontainer_path=.devcontainer%2Factions%2Fdevcontainer.json&geo=UsEast)
2. Run `/workspaces/actions/actions-codespaces/script/server --scenario "actions-codespaces-vnext" --continue-on-error` (this might take awhile)
3. Open a new terminal and navigate to the actions results workspace `cd /workspaces/actions/actions-results`
4. Setup dotcom codespace for actions `./script/setup-dotcom-codespace`
*If you get an error for "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?", try to re-init docker with `/usr/local/share/docker-init.sh`*
5. In a new terminal start the dotcom server `./script/server`
6. In the old terminal inside actions-results, run `./script/setup-billing-platform` to setup billing platform
7. Start billing platform with `./script/start-billing-platform`
8. Open a new terminal and run `./bin/actions-usage-relay`
9. Open a new terminal and run `start-actions`
10. Sync the customer with billing platform to add the customer record to Cosmos by clicking "Sync customer" on the local [stafftool customer page](http://github.localhost/stafftools/enterprises/github-inc/billing).

See [actions-development.md](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md) and [billing-platform-development.md](https://github.com/github/actions-results/blob/main/docs/billing-platform-development.md) for troubleshooting these steps.

### How to produce Actions usage events

#### Dotcom UI

1. Go to [http://github.localhost/github/private-server/actions](http://github.localhost/github/private-server/actions)
2. Create an Action using the default `Simple workflow`
3. Trigger it to run manually

After running this you should see messages coming through in the `actions-usage-relay` terminal as well as the billing platform API and usage ingestion worker.

Troubleshoot this step [here](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md#setting-up-a-test-workflow).

#### Rails Console

1. From Dotcom - `bin/rails c`
2. `GitHub.hydro_publisher.publish({}, schema: "billingplatform.v1.Usage")`
    1. Update the first parameter with data that matches the Proto schema

## FAQ

- **How do you run Actions workflows in a codespace?** In a dotcom codespace, we are only able to run `self-hosted` actions SKUs, because the only runner that is available in a codespace is a self-hosted runner. Billing platform also currently ignores such `self-hosted` SKUs from our rollups so you will be able to see billing platform ingesting the usage but will not see that usage in the UI.

## References

- [Actions Results Usage ADR](https://github.com/github/c2c-actions/blob/main/docs/adrs/4755-results-usage.md)
