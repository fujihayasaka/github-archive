# launch

> **Note**
>
> Unless you're contributing to Launch development, you might find the plans, milestones, and architecture documents in the [`github/actions-launch` repository](https://github.com/github/actions-launch) or on [The Hub](https://thehub.github.com/search/?query=launch+service) more useful.

## What is Launch?

Launch is a set of [Moda](https://thehub.github.com/epd/engineering/products-and-services/internal/moda/) services that acts as a bridge between [Dotcom](https://github.com/github/github) and most of Actions.

Its primary responsibility is to ... launch ... Actions workflows in response to things like API calls, a scheduled time, or GitHub events (commit pushed, pull request opened, issue created, etc).

Launch is comprised of [four main services](https://thehub.github.com/epd/engineering/products-and-services/actions/architecture/launch/):

- **launch-worker**
  - Fetches webhooks from actions-enabled repositories off of multiple Aqueduct queues
  - Determines if a webhook should result in a run being queued with Actions Service
  - Also receives scheduled and dynamic run requests off their respective queues
  - Queues runs with Actions Service.

- **launch-receiver**
  - The only Launch service that is accessible on the public Internet (<https://launch-receiver.githubapp.com/_ping>)
  - Accepts a wide variety of requests from Actions Service, see diagram below

- **launch-deployer**
  - Processes scheduled and dynamic workflows
  - Receives postbacks from launch-receiver and updates Dotcom state
  - Proxies a wide range of requests from Dotcom to Actions Service

- **launch-hydro-consumer**
  - Reacts to Hydro events
  - Example: repository is deleted
    - Cancel pending runs
    - Delete scheduled builds

Launch follows the pattern of [Scripts to Rule Them All](https://github.com/github/scripts-to-rule-them-all) for setup, development, and testing

See [End-to-end Development Environments](./docs/local-dev.md#end-to-end-development-environments) for the preferred environments to develop Launch for end to end use.

## Setup

### Codespaces Setup

Codespaces is the preferred environment for Launch development.

You can create a new codespace either by using [github.com](https://github.com/codespaces) or using the [GitHub CLI](https://cli.github.com/).

You should select `github/github` as the repository and use the Actions devcontainer: `.devcontainer/actions/devcontainer.json`

Example:

```console
gh cs create --machine xLargePremiumLinux --devcontainer-path .devcontainer/actions/devcontainer.json --repo github/github --branch master
```

Inside the Codespace, the Launch source code is located under `/workspaces/actions/launch`.

A in-depth guide to [Actions Development on Codespaces](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md) is available.

### Local Setup

Local development is limited to making changes to Launch in isolation and running Launch specific tests. For end to end development, you will need to use [Codespaces](#codespaces-setup). If you're using Codespaces, you can skip this section.

Ensure [Docker for Mac](https://www.docker.com/docker-mac) is installed (or the version appropriate for your OS).

Ensure Go is installed and `$GOPATH/bin` is in your `$PATH`, see [Setting `GOPATH`](https://github.com/golang/go/wiki/SettingGOPATH) for environment specific instructions.

Ensure [`goproxy`](https://github.com/github/goproxy) is configured. Refer to the [`Set-up`](https://github.com/github/goproxy/blob/main/doc/user.md#set-up) section of [`A user's guide to goproxy`](https://github.com/github/goproxy/blob/main/doc/user.md) for details.

Clone the repository:

```console
git clone https://github.com/github/launch
```

Install dependencies:

```console
script/bootstrap --no-app
```

## Building

To build the Launch service:

```console
script/build
```

## Running

Note: Running the launch service in development is only supported via [Codespaces](#codespaces-setup).

When using the [`start-actions`](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md#bootstrap-actions-) command in your Codespace, the Launch service will automatically be started.

The Launch service state can be managed by using [`service`](https://www.commandlinux.com/man-page/man8/service.8.html) commands:

```console
service launch status
```

```console
service launch start
```

```console
service launch stop
```

Sometimes it is desirable to run the service manually, for example when debugging. To do so, ensure the service is stopped (`service launch stop`), then run the following:

```console
script/server
```

You can monitor the Launch service's log output by running:

```console
tail -f /workspaces/actions/launch/output.log -n +1
```

## Testing

To run the Launch test suite:

```console
script/test
```

For more details on testing, check out this [doc](./docs/testing.md). To run security and functional integration tests ahead of deploying to production, check out [Running integration tests](./docs/testing.md#running-integration-tests).

## Installing dependencies

See [Installing dependencies](./docs/installing-dependencies.md)

## GHES/Enterprise development

See [GHES docs](https://github.com/github/c2c-actions/tree/master/docs/ghes) for options.

## Deploying

See [Deploying](./docs/deploying.md)

## Structure

For a detailed description of the Launch architecture, see [Actions App architecture](https://thehub.github.com/engineering/products-and-services/actions/architecture/actions-app/)

1. [`cmd`](./cmd/) - Entrypoints for the various Launch services
1. [`config`](./config/) - Kubernetes, Moda, and tools configuration
1. [`services`](./services) - Launch service specific business logic
1. [`proto`](./proto) - Our protobuf definitions
1. [`schemas`](./schemas) - Database schemas

## Updating typed GraphQL schemas

For some GraphQL operations, we use [githubv4](https://github.com/github/githubv4) in order to have strong typing for our GraphQL. If you make changes to the GraphQL schema, here's how you update it:

1. Clone [githubv4](https://github.com/github/githubv4) locally and enter the directory.
2. Create a Personal Access Token in github.com with the `site_admin` permission.
    - You will have to log into [Stafftools](https://admin.github.com) and authenticate with a just-in-time (JIT) session before creating the PAT
3. Regenerate the GraphQL schema by running `GITHUB_TOKEN=<token> go generate`
4. If necessary, add new types to [scalar.go](https://github.com/github/githubv4/blob/master/scalar.go)
5. Open a PR to `github/githubv4` with the updated schema and merge it in.
6. Get the most recent version string of `githubv4` after the changes have been merged in by running the following command. The output will be something like `20220510134615-ca77ca1494a3`

    ``` console
    TZ=UTC git --no-pager show \
      --quiet \
      --abbrev=12 \
      --date='format-local:%Y%m%d%H%M%S' \
      --format="%cd-%h"
    ```

7. After the pull request is merged in, update `launch` with the latest version of `githubv4`
   - Replace the old version string with the new one in `go.mod` (keep the `v0.0.0-` at the beggining and only replace what comes after). The line starts with `replace github.com/shurcooL/githubv4 => github.com/github/githubv4`
   - run `go clean -modcache`
   - run `go mod tidy`
   - run `go get github.com/github/launch/clients/github` if you get `missing go.sum entry for module providing package github.com/shurcooL/githubv4`
   - run `script/build` and make sure things still work
   - Commit the output. Here is an example [PR](https://github.com/github/launch/pull/5980)

### Entity relations

See [docs/azure.md](docs/azure.md) for how our entities relate to those in github/github and Actions Service

### Twirp

See [docs/twirp.md](docs/twirp.md) for an overview of Twirp, the development flow, and local testing that will allow you to avoid waiting for updated Twirp clients to be uploaded to Octofactory.
## Four Nines

See [docs/four-nines.md](docs/four-nines.md) for information about launch in the four nines architecture.
