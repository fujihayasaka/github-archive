# Dependency Snapshots API

> To onboard a new repository to use build-time detection/alerting, see [this doc](https://github.com/github/dependency-graph/blob/master/docs/enabling-build-time-detection-and-alerts.md).

> For developer documentation, including database ERDs and dataflow diagrams, see [this doc](./docs/README.md).

This service provides an experimental interface to snapshots that are currently stored by [dependency-graph-api](https://github.com/github/dependency-graph-api).
Its goal is to maintain deeper indexes into the existing snapshots and allow them to be searched and combined.

The tentative long-term plan is for this service for it to take over many of the responsibilities currently handled by [dependency-graph-api](https://github.com/github/dependency-graph-api), and enable new features beyond those.

# How to run it

1. Bootstrap: `./script/bootstrap`
1. Build it: `./script/build`
1. Run it: `./script/server standalone`
    * if you're running this alongside local dotcom, use `./script/server dotcom`

# How to debug it
When debugging, a separate executable is built and run. Debuggers will usually hide this from you (vscode and Delve both do), but you need to replicate any env vars that we normally use in our build process (see Makefile).

1. For command line debugging, you install and run a [Delve](https://github.com/go-delve/delve) command. Delve can end up in `$HOME/go/bin/dlv` or `$GOPATH/go/bin/dlv`.
  `$HOME/go/bin/dlv debug ./cmd/api/`
1. For visual debugging, install the Go extension in vscode and COMMAND+SHIFT+P => `Debug: Start Debugging` . Vscode should automatically load and run our `./.vscode/launch.json` file, and you can set breakpoints throughout the IDE. It will run the server by default, but you can change that at the top of the debugger sidebar by selecting "Launch Worker" rather than "Launch Server".

To debug the integration tests, start the server in debug mode and then run `script/test-integration --no-server`.

# Running in Codespaces

1. [Create a new Codespace on dependency-snapshots-api](https://github.com/github/dependency-snapshots-api/codespaces)
1. Wait for setup to complete
1. Run `script/server` to run the development server
1. The development server is available at `http://localhost:9597/`

#### Trying to run outside the ds-api codespace? `script/setup-go-auth` can help

You may also need to run `export AZURE_STORAGE_BLOB_ENDPOINT="http://127.0.0.1:20100/devstoreaccount1"`.

# How to deploy to prod
Deployment to production uses Heaven Pipelines & Merge Queue. To deploy a pull request, add to merge queue ("Merge when ready") once all checks have passed. The `production_rollout` pipeline will be automatically started and the PR will be deployed to all production environments (dotcom and all Proxima stamps). For more information [see TheHub](https://thehub.github.com/epd/engineering/devops/deployment/onboarding-to-heaven-pipelines/). Keep an eye on #dg-ops and on [monitoring](https://app.datadoghq.com/dashboard/amb-m5t-x7w/ds-api?from_ts=1647959556365&to_ts=1647961356365&live=true).

If you are deploying a high-risk change, you can optionally deploy just a single Moda pod per deploy site as a pre-step to the full deploy using Moda's canary functionality:
* Chatop syntax: `.deploy dependency-snapshots-api/YOURBRANCH to production/canary --ignore-required-pipeline`
* Both [Datadog](https://app.datadoghq.com/dashboard/cpc-97s-ksj/kubernetes-namespaces?tpl_var_kube_cluster=general-1-ash1-iad&tpl_var_kube_namespace=dependency-snapshots-api-production&tpl_var_namespace=dependency-snapshots-api-production) and [Moda Homepage](https://moda.githubapp.com/apps/dependency-snapshots-api/deployments/production?cluster=general-1-ash1-iad) pods will be labeled as `canary` for quick filtering while you observe the risky deploy in production
* After an appropriate burn-in time, roll back to `main` branch, or execute the full deploy.

If you want to deploy to lab environment, run `.deploy dependency-snapshots-api/YOURBRANCH to lab` in #dg-ops.

# How to hit the API
## Locally, REST
1. `curl http://localhost:9597/_ping`
1. `curl http://localhost:9597/boom`

## Locally, twirp
#### DiagnosticService:
- `curl -d {} -H 'Content-Type: application/json' http://localhost:9597/twirp/github.dependency_snapshots_api.DiagnosticService/Ping`
- `curl -d {} -H 'Content-Type: application/json' http://localhost:9597/twirp/github.dependency_snapshots_api.DiagnosticService/Boom`
- `curl -d '{"sleepDurationSeconds": 10}' -H 'Content-Type: application/json' http://localhost:9597/twirp/github.dependency_snapshots_api.DiagnosticService/Timeout`
- `curl -d '{"sleepDurationSeconds": 10}' -H 'Content-Type: application/json' http://localhost:9597/twirp/github.dependency_snapshots_api.DiagnosticService/Timeout`

The following endpoints require some data to be loaded into the database. Run `./script/seed-dev-data` to add a few commits and snapshots.

#### SnapshotsService: CreateDependencySnapshot
Using the `bytes`-typed protobuf `payload`, this is multi-step. Create a JSON payload and pipe it into `base64`, then apply the output string as the `payload` field of your Twirp request body, when submitting as `Content-Type: application/json`. Example:
- `payload=$(cat docs/production-github-samples/sample-snapshot.json | base64 | tr -d \\n );curl -d "{\"repository_id\": 45678, \"payload": \"$payload\"}" -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.SnapshotsService/CreateDependencySnapshot'`

#### SnapshotsService: GetDependencySnapshot
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.SnapshotsService/GetDependencySnapshot' -d '{"repository_id": 45678, "snapshot_id": 2}'`

(replace `2` with the actual snapshot ID)

#### SnapshotsService: GetIncludedDependencySnapshots
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.SnapshotsService/GetIncludedDependencySnapshots' -d '{"repository_id": 45678 }'`

#### SnapshotsService: ExcludeDependencySnapshots
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.SnapshotsService/ExcludeDependencySnapshots' -d '{"repository_id": 45678, "snapshot_ids": [12345] }'`

#### SnapshotsService: GetSnapshotDiff
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.SnapshotsService/GetSnapshotDiff' -d '{"repository_id": 45678, "basehead": "0123456789abcdef0123456789abcdef12345678...abcdef0123456789abcdef0123456789abcdef01"}'`

#### DependenciesService: GetDependenciesForRepository
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.DependenciesService/GetDependenciesForRepository' -d '{"repository_id": 45678}'`
#### DependenciesService: HasManifests
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.DependenciesService/HasManifests' -d '{"repository_id": 45678}'`
#### DependenciesService: RepositoriesContainingDependency
- `curl -H 'Content-Type: application/json' 'http://localhost:9597/twirp/github.dependency_snapshots_api.DependenciesService/RepositoriesContainingDependency' -d '{"base_purl": "pkg:npm/@actions/core", "version_range": ">1.1.1"}'`


## PROD, twirp + HMAC
1. Get an HMAC by running `.dg hmac` in an ops channel.
1. `ssh` to a bastion node or log into prod VPN
1. The request should take the same form as a dev example, updated with the prod URL/scheme and a `Request-HMAC` header using the HMAC from step 1
### LAB-API uses a different host name than production
instead of production's `https://dependency-snapshots-api-production.service.iad.github.net/`
you need to use `https://dependency-snapshots-api-lab.service.ash1-iad.github.net/`
Note the difference in both **host** and **datacenter**

#### Diagnostic
- `curl -H 'Content-Type: application/json' https://dependency-snapshots-api-production.service.iad.github.net/twirp/github.dependency_snapshots_api.DiagnosticService/Ping -d {} -H "Request-HMAC: $HMAC"`
- `curl -H 'Content-Type: application/json' https://dependency-snapshots-api-production.service.iad.github.net/twirp/github.dependency_snapshots_api.DiagnosticService/Boom -d {} -H "Request-HMAC: $HMAC"`

#### Snapshots
- `curl 'https://dependency-snapshots-api-production.service.iad.github.net/twirp/github.dependency_snapshots_api.SnapshotsService/GetDependencySnapshot' -d "{\"repository_id\": $REPO_ID, \"snapshot_id\": $SNAPSHOT_ID}" -H 'Content-Type: application/json' -H "Request-HMAC: $HMAC"`

    (make sure to set PAYLOAD, which can be derived via a `cat docs/production-github-samples/sample-snapshot.json | base64 | tr -d \\n` locally)

- `curl 'https://dependency-snapshots-api-production.service.iad.github.net/twirp/github.dependency_snapshots_api.SnapshotsService/CreateDependencySnapshot' -H 'Content-Type: application/json' -d "{\"payload\": \"$PAYLOAD\", \"repository_id\": $REPO_ID}" -H "Request-HMAC: $HMAC"`

#### Dependencies
- `curl 'https://dependency-snapshots-api-production.service.iad.github.net/twirp/github.dependency_snapshots_api.DependenciesService/GetDependenciesForRepository' -d "{\"repository_id\": $REPO_ID}' -H 'Content-Type: application/json' -H "Request-HMAC: $HMAC"`

## PROD, gh/gh
1. Take a look at [the sample snapshot](docs/production-github-samples/sample-snapshot.json)
1. From here, run `curl -u '<YOURUSER>:<YOURPAT>' -H 'Content-Type: application/json' 'https://api.github.com/repos/github/dep-graph-test-manifests/dependency-graph/snapshots' -d @docs/production-github-samples/sample-snapshot.json`
1. This should create a snapshot, and return to you the snapshot id. You can get it via:
`curl -u '<YOURUSER>:<YOURPAT>' -H 'Content-Type: application/json' 'https://api.github.com/repos/github/dep-graph-test-manifests/dependency-graph/snapshots/<SNAPSHOTID>'`

Or use the [gh cli](https://cli.github.com) to create a snapshot:
1. `gh api repos/$REPO_NWO/dependency-graph/snapshots --input docs/production-github-samples/sample-snapshot.json`
1. `gh api repos/$REPO_NWO/dependency-graph/snapshots/$SNAPSHOT_ID`


# Database migrations
To create a database schema migration:
- Run `script/create-migration <migration-name>`. This will create an up and a
  down migration in the `migrations` directory. Add the SQL for your migration
  to these files. They must contain schema changes only, as data changes won't
  be picked up by our online migration tools.
- Run `script/migrate`. This applies the migration locally and invokes `skeema`
  to record the changes in the `schema` directory.
- Open a pull request. The `schema-diff` action should detect the schema change
  and update the PR.
- Review the proposed changes from the `schema-diff` action.
- Add the `migration:for:review` label to the PR to request review from
  `github/database-infrastructure` and start the process to apply the schema
  changes.
- When the migration is complete, deploy and merge the PR.

# How do I change the DS-API Twirp protobuf specs?
- Make sure you are logged in via `docker login ghcr.io`
  - username: your GH handle
  - password: [PAT](https://github.com/settings/tokens) with `read:packages` checked and SSO enabled
- Run `make proto` to (re)generate Ruby and Go code from the root
- On fail:
    - Fix Twirp/protobuf syntax errors in the spec files if surfaced
    - `script/bootstrap` if you're missing Twirp/proto dependencies
- On success:
    - Stage and commit the proto spec and generated code changes
    - PR and merge
    - See below for how to export DS-API Twirp changes to DG-API

# How do I export DS-API Twirp/protobuf code...

Before all of these, ensure your latest Twirp/protobuf changes (and regenerated Ruby code!) are checked into DS-API `main`

## to DG-API
- Hop into DG-API to checkout, pull latest changes, and cut a new clean branch from `master`
- Run the `vendor-gem` script from DG-API repo root, pointing it at DS-API's `gemspec`, default branch, and GH URL
  - Example: `script/vendor-gem -r main -p gen/ruby -n dependency-snapshots-api-proto https://github.com/github/dependency-snapshots-api`
- Stage and commit the resulting generated code on your new DG-API branch

## to DGP
- Hop into DGP to checkout, pull latest changes, and cut a new clean branch from `master`
- Run `go get github.com/github/dependency-snapshots-api`. It should pull the sha of the main branch by default.
- Stage and commit the resulting generated code on your new DGP branch

## to dotcom
- Grab the sha of the main branch in DS-API
- Hop into gh/gh to checkout, pull latest changes, and cut a new clean branch from `master`
- Open the Gemfile and update the `ref` for `dependency-snapshot-api-proto` with the new sha
- Run `bundle install` to install the gem
- Run `bin/tapioca dsl` to regenerate the sorbet files
- Stage and commit the resulting generated code on your new DS-API branch

For all of them, if these are breaking changes, continue to iterate on your branch with related code updates. When tests are passing, open a new PR.

# How do I show the gh/gh end to end locally?
1. Bootstrap a clean dotcom checkout, and run the server + DG config vars: `DEPENDENCY_GRAPH_API_URL=http://localhost:9596/query DEPENDENCY_GRAPH_API_SLOW_QUERY_URL=http://localhost:9596/query script/server`
1. Set up DG-API repo (to proxy requests/responses between dotcom and DS-API)
1. Dotcom instance UI:
    1. Create a new repository for `monalisa` user on running `github.localhost`
    1. Create/obtain monalisa PAT token with repo permissions for API use
1. Enable feature flags for this repo/owner in your local dotcom env. Example:
```bash
bin/toggle-feature-flag enable dependency_graph_build_snapshots monalisa
```
1. Trigger a dotcom snapshot via the API. Example:
```bash
curl -u 'monalisa:<PAT>' 'http://api.github.localhost/repos/monalisa/<YOUR_REPO_NAME>/dependency-graph/snapshots' -d '{"job":{"id": "FOOBAR", "correlator": "tester"}, "scanned": "2021-10-31T10:31:00-08:00", "sha": "07927161d8e129ba98b587ea17c3bbfb29b9e3e5", "ref": "refs/heads/main", "version":1, "detector":{"name":"sample-detector", "version":"1.0.0", "url":"http://example.com/sample-detector"}}'
```

# How do I consume github.localhost Hydro events in DS-API?
These steps are tailored to our current use case, consuming RepositoryPush events published by the monolith. This checklist will be updated when DS-API begins consuming additional event streams, and when we add a tool for directly publishing events locally. Note: these instructions _do work_ with github/github running in Codespaces.
1. Ensure your `github/github` checkout is up to date, `script/server` is running
1. In the DS-API checkout: `make build; script/server dotcom` to run the worker and API DS binaries, and configure to consume events from `github.localhost`
1. Browse `github.localhost`, login as `monalisa`, create a new repository if needed
1. Push a _manifest file change_ to the new repo and await an event to be published!

#### Troubleshooting
- If you see the `github.localhost`'s `script/server` logs showing Kafka errors related to API version when `ds-worker` is running, check that you ran `ds-worker` with the `KAFKA_LITE_COMPATIBLE=true` env var set.
- If you find `github.localhost` event publishing isn't working, check that [script/kafka-lite-server](https://github.com/github/github/blob/master/script/kafka-lite-server) ran successfully and `kafka-lite` process is up

#### Direct Event Publish
It's possible to use your local Rails dotcom console to publish push events too. I had some trouble with this locally due to notifications plumbing (timing instrumentation wrappers on the global instrumenter) not working in local env :( but I'll update this when we have a tool/script of our own.
- Example [here](https://github.com/github/github/blob/3a7e9b331e5cd1869a409cfb171cfd5a5f837bf7/packages/repositories/app/models/push.rb#L296-L312)
- IMPORTANT - ensure all event fields referenced in the _consumer job_ are well formed or you'll need to clear out the topic (or skip the consumer group ahead in your local) to avoid head of line blocking!

# How do I show the gh/gh end to end in production?
1. Follow the instructions in the build time alerting doc at the top of the README!
