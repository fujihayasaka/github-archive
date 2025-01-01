# Blackbird Middleware

This repository contains middleware for the [blackbird][] code search engine.

* Ingest pipeline (blackbird-ingest)
* Query server (blackbird-query)
* Admin/chatops server (blackbird-admin)
* Probers (blackbird-prober)
* Maintenance job (blackbird-maintenance)

See the overall [architecture of the system](https://github.com/github/blackbird/blob/main/docs/architecture.md) to get oriented.

## Getting started

1. Make sure [direnv][] is allowed to load [`.envrc`](./.envrc) (required environment variables). If you're going to manually manage your environment, check out [`.envrc`](./.envrc), [`.env`](./env) and the [goproxy docs](https://github.com/github/goproxy/blob/main/doc/user.md#workflow-personal-machine-laptop) since we use private Go dependencies.
   ``` sh
   direnv allow
   ```
1. Bootstrap for initial setup or if the clibs change.
   ``` sh
   make bootstrap
   ```
1. Use standard Go commands to develop (or check out the [`Makefile`](Makefile)).
   ``` sh
   go build ./...
   go test ./...
   ```

## Docker and docker-compose

Docker is required to run the db and integration tests. You'll need to be logged in to the GitHub Package Registry to pull docker images. See the [official docs](https://docs.github.com/en/packages/guides/configuring-docker-for-use-with-github-packages#authenticating-with-a-personal-access-token) for details, but the tl;dr; is:

```
# Create $PAT as a legacy token with package:read permissions and SSO for the GitHub org.
echo $PAT | docker login ghcr.io --username USER --password-stdin
```

### Run the integration tests

``` sh
make test-integration
```

This will start all dependent services, including blackbird and blackbird-mw before running the integration tests which do a couple of backfills and assert various queries.

### Run the db tests

``` sh
make test-db
```

### Connect to MySQL

MySQL runs in the docker compose environment.

```
mysql --host 127.0.0.1 --port 9945 --user root --database blackbird_test
```

### spokesd

We leverage the [spokes-proto][] project (it's included as a submodule in [deps](./deps)) in order to provide a local spokesd+gitrpcd environment. When you run blackbird-ingest's `script/setup` you're starting up two environments:

1. spokesd, gitrpcd, mysql
2. blackbird-indexer, blackbird-server, kafka, zookeeper, mysql, redis

Repositories are mounted to [deps/spokes-proto/repositories](deps/spokes-proto/repositories) which allows you to clone and push if needed. See the spokes-proto [readme](deps/spokes-proto/README.md) for more details including how to add new repositories into the system.

All the normal `docker compose` workflows should work as expected.

### Admin site

You can test the admin site locally with fake data.

> **NOTE:** We currently use "classic" Yarn 1.x. If you use the version of Yarn distributed with NPM [corepack](https://github.com/nodejs/corepack), it will result in a giant diff in yarn.lock and some new cache directories.

1. Change into the `admin-frontend` directory.
2. Install/update dependencies:
   ```
   yarn install
   ```
3. Start the fake data server:
   ```
   yarn server
   ```
4. In another terminal, start the React server:
   ```
   yarn start
   ```

To view/modify the fake data see [server/index.js](https://github.com/github/blackbird-mw/blob/main/admin-frontend/server/index.js).


## Production

The blackbird-mw production [Moda](https://moda.githubapp.com/apps/blackbird-mw) environments are broken down as follows:
- Production
   - query
   - admin
   - prober
   - maintenance
- Lab
   - query
- Blue<sup>†</sup> / Green<sup>†</sup> / Yellow / Red / Orange / Violet
   - ingest

<sup>†</sup> Blue and Green are the only ingest environments deployed to Proxima stamps.

The typical deploy workflow is to use the Merge Queue, which executes the [Heaven Deploy Pipeline](https://thehub.github.com/epd/engineering/devops/deployment/onboarding-to-heaven-pipelines/) defined in [`config/moda/deployment.yaml`](./config/moda/deployment.yaml). Only Production and Blue and Green are directly deployed by the pipeline. The other environments are auto-deployed after the pipeline finishes. This is best-effort and may fail. It _will_ fail if the environment is locked.

Between stages of the deploy pipeline, we use [Datadog gates](https://thehub.github.com/epd/engineering/dev-practicals/safe-deployment-practices/#custom-datadog-gates) to prevent regressions. If a gate fails, you can see the logs for the GitHub Action that ran it in the [github/heaven-gates](https://github.com/github/heaven-gates) repo.

You can also do branch deploys in the `#blackbird-ops` channel to deploy blackbird-mw. Use the `.deploy` chatop to publish to a single environment:

```
.deploy https://github.com/github/blackbird-mw/pull/nnn to <env>
```

 `env` is one of `production`, `lab`, `blue`, `green`, `yellow`, `red`, `orange`, or `violet`, plus their Proxima equivalents like `staff-wus2-01`, `staff-wus2-01-blue`, or `staff-wus2-01-green`.

Use experiment `use_lab_middleware=1` from github.com search to test changes and [see logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3D%22blackbird%22%20kube_namespace%3D%22blackbird-mw-lab%22&earliest=-60m%40m&latest=now&display.page.search.mode=smart&dispatch.sample_ratio=1&sid=1666798832.152454_C0C5B915-8848-4B1E-9690-270AE5D8547F) in lab.

### blackbird-ingest

In production, blackbird-ingest consumes from Kafka topics in the Potomac cluster:
- [`blackbird.v0.BlackbirdBackfillBlue`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=blackbird.v0.BlackbirdBackfillBlue), [`blackbird.v0.BlackbirdBackfillGreen`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=blackbird.v0.BlackbirdBackfillGreen), [`blackbird.v0.BlackbirdBackfillYellow`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=blackbird.v0.BlackbirdBackfillYellow), [`blackbird.v0.BlackbirdBackfillRed`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=blackbird.v0.BlackbirdBackfillRed)
- [`blackbird.v0.BlackbirdOnboard`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=blackbird.v0.BlackbirdOnboard)
- [`cp1-iad.ingest.github.search.v0.RepositoryChanged`](https://hydro.githubapp.com/kafka/clusters/potomac/topic?topic=cp1-iad.ingest.github.search.v0.RepositoryChanged)

The backfill topics are published to by [blackbird-admin](https://github.com/github/blackbird-mw/blob/main/internal/admin/service.go), the onboard topic is published to when a new repository needs to be indexed (and by lazy indexing), and the `RepositoryChanged` topic is published to by GitHub when repository changes that require search updates happen.

- [Datadog dashboard](https://app.datadoghq.com/dashboard/nnf-hsw-z7s/blackbird-ingest)
- [Splunk logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?earliest=-60m%40m&latest=now&q=search%20index%3Dblackbird%20kube_namespace%3Dblackbird-mw-production%20app%3Dblackbird-ingest&display.page.search.mode=smart&dispatch.sample_ratio=1)

### blackbird-query

In production, blackbird-query serves traffic for all the corpora/clusters but at any given point we only serve a single corpus/cluster. You can check what's currently being served by running the `.blackbird status` chatops or visiting the [admin site](https://blackbird.githubapp.com/).

- [Datadog dashboard](https://app.datadoghq.com/dashboard/7yr-8jp-kf3/blackbird-query)
- [Splunk logs](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dblackbird%20app%3Dblackbird-query&sid=1666798032.152298_C0C5B915-8848-4B1E-9690-270AE5D8547F&display.page.search.mode=smart&dispatch.sample_ratio=1&earliest=-15m%40m&latest=now)

### Database

blackbird-mw's database is a [production Vitess cluster](https://professorx.githubapp.com/mysql/cluster/blackbird-production).

You can log into the cluster like this:

```bash
# Get the password at https://professorx.githubapp.com/mysql/cluster/blackbird-production
mysql -h vtgate-blackbird-production.vitess-production.service.github.net -P 3306 -u blackbird_production_rw_1 -p blackbird_ks
```

Since this is a production cluster, the users we have access to do not have permission to change the database schema.

#### Changing the database schema

We use [Skeema](https://www.skeema.io/) to manage our database schema changes. It is installed for you by `script/bootstrap`. To update the local database schema run the docker compose environment with `script/setup`:

```bash
script/setup --test
```

To update the production database schema:

1. Create a PR with a schema change.
2. The `skeema-diff` GitHub Actions workflow will detect the skeema change and add a comment.
3. Review the PR. Once it's ready, add the label `migration:for:review`.
4. A database-infrastructure engineer will approve the PR and the migration will be run.

   **NOTE:** This process can take 1-2 business days. You can ping [#databases](https://github.slack.com/archives/C0FHZDN13) on Slack if it's urgent.
5. Once the migration is complete, deploy and merge the PR.

For more details, check out [the skeefree documentation](https://github.com/github/skeefree/blob/master/docs/how.md#the-flow-tldr).

## Dependencies

Dependabot is [configured](.github/dependabot.yml) to keep Go, Docker, Npm, and Actions up-to-date. Sometimes it can be more efficient to batch updates into a single PR which can be done manually for each ecosystem. If CI passes, most updates are safe to branch deploy, but please read the release notes and changes logs and be especially careful with these two dependencies:

- [sarama](https://github.com/IBM/sarama)—We've had numerous historical issues with upgrading sarama causing breakage or subtle performance problems.

## Blackbird's C APIs

We expose a number of C APIs from [blackbird][] that are consumed in the middleware. These APIs are consumed via Go packages that are maintained in the [blackbird][] repo. This allows developing algorithms once in Rust and then sharing implementations between blackbird (Rust) and blackbird-mw (Go). The static libraries are:
  - `libblackbird_core.a` (geofilter)
  - `libblackbird_client.a` (dynamic shard assignment client)
  - `liblinguist.a` (Rust implementation of linguist)

We expect these libraries to be installed to `./lib` and it's important that the Go packages and c libraries they depend on stay in sync. In CI and our production systems, blackbird-mw's Dockerfile copies the static libraries into the right place. In local development, [the bootstrap script](script/bootstrap) installs the static libs. Source [.envrc](./.envrc) to properly set `CGO_LDFLAGS` (or use [direnv][] and this'll happen automatically for you).

Integration tests require both that the static libraries are installed on the system **AND** that the docker containers are built with the same versions of the static libraries. These may be different binaries—for example if your host system is macOS, you'll have a Darwin build of the static libraries for running the unit/integration tests, but a Linux version installed in each docker container that makes up the docker compose integration test environment.

### Updating blackbird_core, blackbird_client, or linguist

To update the clibs and their Go packages:

1. Update the installed static libraries on your host system which you can do with `script/bootstrap` or by running `script/install-blackbird-clibs` from the [blackbird][] repo.
2. Update the go package(s) with `script/update-blackbird-packages`. For branch changes, you can use `script/update-blackbird-packages <branch name>` -- but make sure you've manually triggered the Release workflow for that branch if you want CI to work.
3. Commit the results.

### To develop changes in the C APIs

[See documentation in the blackbird repo](https://github.com/github/blackbird/tree/main/docs/clibs.md).

[blackbird]: https://github.com/github/blackbird
[spokes-proto]: https://github.com/github/spokes-proto
[direnv]: https://direnv.net/
