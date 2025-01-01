# turboscan

TurboScan is the backend service that powers Code Scanning on GitHub.com and GitHub Enterprise Server. It is responsible for processing [SARIF files](https://docs.oasis-open.org/sarif/sarif/v2.0/sarif-v2.0.html) that are submitted by GitHub Actions or third-parties, and tracking the alerts contained within them through their life from introduction to resolution. It also provides internal APIs for all the Code Scanning data you see in GitHub or can access via the [public GitHub Code Scanning API](https://docs.github.com/en/rest/reference/code-scanning).

## Development

To develop Turboscan, follow the [instructions to use `codespace-compose`](https://github.com/github/code-scanning/blob/main/docs/running-your-own-instance.md#codespaces-all-the-things-recommended), the officially supported development flow. It will run a `github/github` Codespace and a `github/turboscan` Codespace, interconnected.

That page also lists alternative unsupported ways to run the project, including how to run Turboscan locally.

### Getting started with Go

- [Effective Go](https://golang.org/doc/effective_go.html)
- [How we Go at GitHub](https://github.com/github/go/blob/main/docs/README.md)
- [GitHub's Go Libraries](https://github.com/github/go)
- [Go Tutorial](https://tour.golang.org/)

### Package documentation

You can generate a Graphviz diagram representing the internal package hierachy using:

```shell
./script/package-diagram
```

### Pulling Kafka-lite and Aqueduct-lite

In order to test Hydro and/or Aqueduct locally, we need to pull those docker images from a private docker registry. Therefor prior to running scripts like `dev-hydrosvc` or `services` we need to login to the right registry.

Replace <token> with a PAT with *registry permission* and *SSO*
Rplace <username> with your username

```shell
export GITHUB_TOKEN=<token>
echo $GITHUB_TOKEN | docker login ghcr.io -u <username> --password-stdin
```

To test it worked, you can pull those images with the following command:

```shell
docker compose --profile processor pull
```

### Testing the NewAnalysis Hydro consumer locally

After the project is setup, run, to start kafka and the hydro consumer:

```shell
script/dev-hydrosvc
```

Than to post messages to it, run the parse-sarif:

```shell
KAFKA_BROKERS=localhost:9092 bin/parse-sarif -repo 45 -commit 32479f1e9ece1a6080a815ef307a484319a2dadb -kafka ts/sarif/testdata/example3.sarif
```

That will produce a message to hydro, and the consumer should consume it and store it in the database.

### Testing Aqueduct locally

Firstly start the dependencies:

```shell
docker compose --profile processor --wait
```

Note: if you get a 'ERROR: ... denied', make sure you did the 'Pulling Kafka-lite and Aqueduct-lite' step.

Now start the aqueductsvc

```shell
./bin/aqueductsvc
```

### CoCoFix

#### Updating CoCoFix

To update the version of CoCoFix being used, run `npm --prefix ./ts/cocofix/javascript/ install @github/cocofix@{desired version}`.
Then run `make cocofix` command. This will bundle cocofix and run integration tests, therefor some environment variables need to be set:

- GITHUB_TOKEN: Create a github classic token, or if you're running in a Codespace this is provided for you.
- COPILOT_ADVANCED_SECURITY_HMAC_KEY: Several options. Use whichever is most convenient.
  - Find this key on the 1Password code-scanning shared vault.
  - Use the shell vault: `vault-secret --application turboscan --environment production -k COPILOT_ADVANCED_SECURITY_HMAC_KEY_DEV`

The `COPILOT_ADVANCED_SECURITY_HMAC_KEY` credential is used to make LLM calls via the Copilot API and is shared across all security AI features (autofix, automodel, secret scanning, etc). The prod and dev variants can also be found in the 1Password codeql shared vault.

#### Running CoCoFix locally

To run CoCoFix locally:

```bash
CAPI_DEV_KEY=$COPILOT_ADVANCED_SECURITY_HMAC_KEY cocofix --sarif ts/cocofix/testdata/reflected-xss.sarif --source-root ts/cocofix/testdata/src --format json --dev
```

### Elasticsearch

#### Testing Elasticsearch locally

If you've run `script/setup`, you should already have an instance of Elasticsearch running locally.
It can be queried directly by calling:

```shell
curl -u elastic:changeme 'http://localhost:9402/'
```

Turboscan has several mechanisms of indexing alerts to Elasticsearch:

* the `bin/repo-indexer` script which creates and configures the Elasticsearch index and indexes alerts in batches
* the `bin/hydrosvc` Hydro consumer, which listens for new analysis events and indexes them individually
* individual Twirp RPC requests like `SetAlertsStatus` might also update the index

If you want to make sure your index is set up correctly and includes all the alerts from the MySQL database, you can run:

```shell
bin/repo-indexer --target=oldest --autoUpgrade --skipRepoSync
```

#### How to extend the Elasticsearch alert index

When the Elasticsearch alert index needs to be changed (e.g. to add a new field), it needs to be upgraded on
all environments. The considerations and design of the upgrades are described in the [org-level ADR](https://github.com/github/code-scanning/blob/main/docs/adrs/0015-org-level-api.md#reindexing-without-downtime).

Below are the concrete steps to take if one is adding a new field:

1. Create a PR that makes the changes the index to start writing the new data ([Example PR](https://github.com/github/turboscan/pull/6776)), this PR should:

    a. Update `orgLevelIndex` in `ts/elasticsearch/index_config.go` increasing the number of the index name (e.g. turboscan-7 to turboscan-8).

    b. Update `orglevelMapping` in `ts/elasticsearch/index_config.go` giving the new field a type.

    c. Update `SearchDocument` in `ts/search.go` to add the new field to the go representation of the document.

    d. Update `SearchDocumentsFromAlerts` in `ts/search.go` to make sure the new field is written when indexing is done. NOTE: make sure that the data is available in the loaded logical alert (possibly by extending the loading in `NextBatch` in `ts/mysql/alert/loader.go`).

2. Add tests for the new field and manually verify the upgrade in development (see below).
3. Deploy the PR, and observe that the following happens when the indexer runs (see the runbook on how to [query ES in production](https://github.com/github/ops/blob/master/docs/playbooks/github/code-scanning/runbook.md#elasticsearch)):

    a. That a new index is created in production (using the `_aliases` endpoint).

    b. That the read index is still pointing to the old index (using the `_aliases` endpoint).

    c. That the write index is pointing to the new index (using the `_aliases` endpoint).

    d. That the mirror index is pointing to the old index (using the `_aliases` endpoint).

    e. That the new index is receiving data (using the `_counts` endpoint)

4. Keep an eye on the org-level dashboard https://app.datadoghq.com/dashboard/qdu-ztf-itv/code-scanning-org-level-api for any degradations in performance or elevated error rates.
5. After the upgrade finishes (2-3 days). Observe that the following has happened:

    a. The read index is pointing to the new index (using the `_aliases` endpoint).

    b. The write index is pointing to the new index (using the `_aliases` endpoint).

    c. The mirror index is pointing to the old index (using the `_aliases` endpoint).

6. Manually re-index problematic repos (see below).
7. Validate that there are no problems with the new index (allowing a few days for problems to manifest).

    a. If there are problems which needs to be fixed urgently, we can rollback the index (see below).
    b. If there are no problems then the old index can be deleted, by running the repo indexer with the `allowDelete` flag in a production shell:

      ```bash
      /app/bin/turboscan cronjobs exec repo-indexer --autoUpgrade --allowDelete
      ```

    c. Repeat the delete command on all proxima hosts to make sure the old indexes are also cleaned up there. Accessing a production shell there is easy with `ts-shell`, e.g.:

      ```bash
      ts-shell --stamp staff-wus2-01
      ```

    d. Validate that the indexes are gone using [the org-level dashboard](https://app.datadoghq.com/dashboard/qdu-ztf-itv/code-scanning-org-level-api) and the "All turboscan indexes (all clusters)" table.

Note: only after the read index have been moved to point to the new index (after step 5) should
the new field be queried.

#### How to verify an upgrade in local development

Here is a example of a series of steps that can be taken to verify an upgrade in local development.
The exact steps depend on what is being added, and it is also possible to e.g. skip the codespace-compose part if one already has data in the database.

1. Set up codespace-compose - running on the commit before the indexing changes.
2. Run `bin/seed code_scanning --organization`
3. Choose some alerts to focus on and make sure that they are in a state to contain the new data.
4. Validate the ES documents for those alerts in the old index using something like

   ```bash
   curl -u elastic:changeme 'http://localhost:9402/turboscan-read/_doc/44' where 44 is the logical alert id of the chosen alerts.
   ```

5. Switch to the branch with the new index and run `script/server` (this bit runs the ES migration)
6. Fetch the documents again from ES and observe that the values of the new fields match their expected values.

Note: it is also possible to inspect the indexes directly without going via the read alias. This is done by replacing `turboscan-read` with the actual index (e.g. `turboscan-7`).

#### Manually reindex problematic repos

Unfortunately some repos are so large (in terms of logical alerts) that they cannot be indexed fully in normal operation without impacting the other repos too much. So the regular indexer only performs a partial index of them.
While we havent had any customer feedback on this, it unfortunately causes problems for security overview in terms of their reconciliation and monitoring.
See https://github.com/github/code-scanning/issues/14460 for more details.

We are working towards a better datamodel and limits that should allow us to reindex these repos again, but until that lands we'll attempt to manually index the problematic repos when we upgrade:

1. Find the problematic repos in Splunk with the following query (over 7 days):

   ```text
   index=turboscan "Reached indexing maximum, stopping load" | top limit=1000 gh.repo.id
   ```

2. Reindex each repo manually by running the repo indexer in a production shell (note that each can take a while, so running with `ts-shell` is recommended):

   ```bash
   /app/bin/turboscan cronjobs exec repo-indexer --target=repo --alertStep=500 --repoID=<REPO_ID> --skipIndexingLimits
   ```

Note that some repos will take a lot of time. There is a repo with more than 17M alerts, it taking several days is not surprising.
The datadot query: https://data.githubapp.com/sql/share/ac65cc51 can give some insight into the size of the repos which correlates with how long the indexing takes.

#### How to rollback an ES upgrade

See https://github.com/github/code-scanning/issues/7092 for the production test of this.

If there is a broken upgrade then revert the faulty PR (reverting to the old index name) and deploy it.
The indexer should then pick up the old name and do a migration back to that.

### Cron jobs

We have a `cronjobs` executable which we use to run our cron jobs:

```shell
/app/bin/turboscan cronjobs exec <job-name> [options]
```

#### Creating a new cron job

1. Create a new directory under `/cmd` for your task
2. Add an empty `main.go` and an appropriately-named file in a `root/` subdirectory.
3. To give these files their content, adapt an existing job to see how to do command-line arguments, code structure and so on
4. Add your new job to `cmd/turboscan/cronjobs.go`
5. Add a configuration YAML file in `config/kustomize/_base/cronjobs/` (again, you can copy an existing one)
6. Add a reference to the new YAML file to `config/kustomize/_base/kustomization.yaml` and run `script/check-generated-files`

##### Adding the cron job to GHES

You'll need to make changes in the enterprise2 repo for your cron job to run on GHES: [Example PR](https://github.com/github/enterprise2/pull/41710).

Note that the files in enterprise2 are Consul templates that are then rendered into Nomad job files so there is another layer of abstraction on top.

- [Nomad job specification docs](https://developer.hashicorp.com/nomad/docs/job-specification)
- [Consul template syntax](https://github.com/hashicorp/consul-template/blob/main/docs/templating-language.md)

###### Testing your cron job's enterprise2 PR

You'll want to test that your job runs in GHES. To do that, launch a [bp-dev](https://thehub.github.com/epd/engineering/devops/bp-dev/) instance and run it there:

1. Run the chatop `.bp-dev launch ghe`
2. Once the instance has been created, log in and checkout your enterprise2 branch

3. Update the Turboscan instance with `./script/update-service.rb turboscan <latest-sha>` and then commit the changes to your PR branch.

4. Rebuild the instance:

```shell
$ ./chroot-stop.sh
$ ./chroot-reset.sh
$ ./chroot-build.sh
$ ./chroot-start.sh
$ ./chroot-configure.sh # go and do something else as this one takes a while!
```

5. Run the job:

```shell
$ ./chroot-ssh.sh
$ nomad job periodic force <your-job-name>
```

6. Next step is to check the logs. Run `nomad status` to find the job name - its ID will end in `/periodic-*` and its Type will be `batch` (not `batch/periodic`).
7. `nomad logs -job <the ID you found>`

#### Running a job locally

```shell
$ make build
[build output omitted]

$ ./bin/turboscan cronjobs exec <job-name>
```

#### Manually invoking cron jobs on production

You might want to manually invoke a cron job on production for testing.
For example, running it in the staffship environment.

To do that, log into an ops shell, run `. vault-login` and `kubelogin config`, and then invoke the cron job with a command like the following:

```shell
kubectl --context <context> --namespace <namespace> create job --from=cronjob.batch/<job-name> <pod-name>
```

- `<context>` should be a context from the list given by `kubelogin config`. For turboscan, try one of the `general-*` ones.
- You can find the possible values for `<namespace>` by looking at the `terraform/**/main.tf` files in this repository. Use the value under `backend "remote"` > `workspaces` > `name`.
- `<job-name>` should match the `name` value under `metadata` in the relevant YAML file in `config/kubernetes/<env>/cronjobs/`
- Choose a `<pod-name>` that's descriptive and works well for searching in logs etc. For example, the job name prefixed by `<your-handle>-test-`.

> [!TIP]
> You can list all namespaces in a context with `kubectl --context <context> get namespaces` to ensure the namespace you want is in the context you want.

For example:

```shell
kubectl --context proxima-1-staff-wus2-01-az1 --namespace turboscan-staff-wus2-01 create job --from=cronjob.batch/turboscan-codeql-garbage-collector sampart-test-turboscan-codeql-garbage-collector
```

### Testing The GitHub UI with prerecorded test data

This repository contains a mock version of Turboscan that will send prerecorded test data called Turbomock.

Turbomock is useful if you are developing a UI feature in github/github and you want control over the data Turboscan is
returning without having to seed and modify the database.

Mock behaviour is defined in `cmd/turbomock/services`.

The cassettes used by Turbomock are defined in `ruby/spec/fixtures/vcr_cassettes/code-scanning`.

From your github/github codespace, you can run `script/turbomock` to start Turbomock. The Turboscan project will be
checked out into the `vendor/turboscan` directory.

### Generating test data

The `bin/parse-sarif` command [can simulate a Code Scanning upload against TurboScan](#ingesting-a-new-sarif-file-in-development) without needing a monolith instance.

If you're running a monolith Codespace that can access a TurboScan then you can run `script/seed code_scanning` from
a monolith Terminal to create a repository with some alerts.

Alternatively you can use [TurboTest](https://github.com/github/turbotest), a tool which runs through various integration
tests. You can get TurboTest to leave the data after running the tests by passing `--cleanup skip`.

### Running tests

Run `make test` to run the Go tests. This will run locally by default,
you can prefix it with `./script/dev-run` to run it in Docker instead.

To run the Ruby tests against the gem code, run `./script/test-ruby`.

Note that [build flags](https://golang.org/pkg/go/build/#hdr-Build_Constraints) are used to control which tests are built (and thus run) locally and on CI. Some tests that require external dependencies are only run on CI. Search the codebase for `//go:build` to see them.

To turn on verbose test logging, change the level in [`dbtest.Logger`](https://github.com/github/turboscan/blob/main/ts/dbtest/dbtest.go).

To turn on verbose mysql/elasticsearch logging, run `script/setup` with the environment variables `MYSQL_LOG_LEVEL=3` and `ES_LOG_LEVEL=DEBUG` set.

#### Inspecting the contents of the database during a test

If you want to inspect the contents of the database during a test, you'll need to:

1. Replace `dbtest.RequireConnection(t)` with `dbtest.RequireConnectionWithoutTransaction(t)` - otherwise no data will show up
2. Set a breakpoint
3. While paused at that breakpoint, run `script/mysql` in terminal
4. Run `use turboscan_test` in MySQL so you're looking at the right database.
5. Examine the data

### Running tests to inspect code coverage

Using `make test-cover` yields local code coverage information, i.e. it reports for each package how much *of that package* is covered by the tests *in that package*.

Using `make test-cover-profile` generates a profile file `testcoverage.out` which includes profile coverage for the whole codebase. The output on the command line itself informs for each package how much of the total codebase the tests in that package cover. (That information is basically useless.) However, the generated profile can be queried to get test coverage information for each function and a total with `go tool cover -func=testcoverage.out`. You can also open a browser to inspect which lines are covered with `go tool cover -html=testcoverage.out`.

### Running the linters

You can run the full lint setup in Docker using `make lint`, however this can be quite slow on a Mac due to the filesystem sharing.

If you only want to run the golang linters it is a lot faster to invoke `go tool golangci-lint run` from the repository root.

### Generate mocks for tests

Run `script/mocks` to update an interface mock used in tests. The
interfaces to be mocked are specified in that script.

### Generating the .proto go definitions

If you need to change the Twirp API definitions, you would change the *.proto files under `proto/` folder, and regenerate their representation in code via: `script/protoc`.
Please consider documenting the `*.proto` files where appropriate as documentation is automatically generated from them by the `protoc` script. Furthermore, there are some
linting rules with the purpose of standardising our `*.proto` files and ensuring that these standards are met. This check isn't currently enforced but
it is encouraged to run using the `make protolint` or `script/protolint`.

### Generate deep-copy methods

Run `script/deep-copy` to generate a `.DeepCopy()` method for the types specified there. If you change any type or need a DeepCopy method, you would want to run this.

### Make changes to SARIF schema

The sarif schema files live in subfolders unders `ts/sarif` folder.

- `ts/sarif/internal/v2_1_0_csd2` is the latest schema we are using. That is the baseline schema.
- `ts/sarif/v2_1_0_turboscan` is actually what turboscan will use, as that is a subset of only the necessary SARIF properties used throughout the code.

To make changes to the turboscan SARIF struct, change the `ts/sarif/v2_1_0_turboscan/v2_1_0_turboscan.json` file, and run `script/go-generate`.

#### Hydro Schema

To update the go Hydro protobuf definitions, run:

```shell
export GOPRIVATE=github.com/github/hydro-schemas-go
go get -u github.com/github/hydro-schemas-go@latest
go mod vendor
```

To regenerate the Ruby stubs in dotcom monolith run:

```shell
GITHUB_PATH=../github # This will change depending on where you have github and hydro-schemas checked-out
[hydro-schemas]$ script/generate --ruby-out $GITHUB_PATH/lib $HYDROS_SCHEMAS_REPOSITORY/proto/hydro/schemas/turboscan/v0/alert_event.proto
```

### Connecting to the local database

Using the mysql command line client: `mysql -u root --port 13307 --protocol=tcp`, or using `script/mysql`.

### Accessing the read endpoints in development

To test one of the read endpoints, run a command like the following:

```shell
curl "http://localhost:8888/twirp/github.turboscan.Results/GetAlert" --header "Content-Type:application/json" --data '{"number": "41", "repository_id": 227161799}'
```

```shell
curl "http://localhost:8888/twirp/github.turboscan.Results/GetAlerts" --header "Content-Type:application/json" --data '{"Coid": 227161799, "commit_oid": "22a31c7b369650b4823c8d7137832c15a529778d", "rule_severity": "WARNING", "repository_id": 227161799}'
```

### Ingesting a new SARIF file in development

Testing of the upload logic can be done by running the `parse-sarif` command:

```shell
./bin/parse-sarif -repo 123 -commit 32479f1e9ece1a6080a815ef307a484319a2dadb ts/sarif/testdata/example.sarif
```

### Writing custom CodeQL queries

Ensure that you have https://github.com/github/codeql and https://github.com/github/codeql-go cloned next to the turboscan repository and open the [custom query development workspace](custom-queries.code-workspace). Then open an existing query in [.github/queries/codeql]([.github/queries/codeql]) or create a new one, and enjoy!

## Database Sharding

We are preparing to shard the database by repository ID to handle the increasing amount of resident data. This creates multiple partitions that exist in separate MySQL instances/schemas which are then accessed indirectly via [Vitess](https://vitess.io/), a MySQL proxy.

Routing rules are used to present a unified, logical schema which Turboscan accesses via a single connection pool. Although this simplifies database access, when writing database queries the author must consider where the data is located. Tables in different partitions cannot be joined against each other.

## Other parts of the project

### TurboScan Client gem

`ruby/lib`: contains the code made available to GitHub itself as a gem - GitHub [calls methods](https://github.com/github/github/blob/master/lib/github/turboscan.rb) on `Turboscan::ResultsClient` and other clients for Managed Analyses (default setup) and Suggested Fixes (autofix), defined in `ruby/lib/turboscan.rb`.

The creation of the gem is controlled by `turboscan-client.gemspec` in the project root.

If you make changes to the gem's code and need to update GitHub's version of it, you need to update the turboscan-client gem in github/github.
You do that by updating the `ref` of the turboscan-client gem specified in the Gemfile in github/github. That part looks like this:

```ruby
gem "turboscan-client",    github: "github/turboscan", ref: "9456567b7327bbc0230d3aa0b791f0dfd17a2cfc"
```

After manually updating `ref` to point to the latest SHA, you need to run `bin/bundle`.

You will most likely also need to run the following commands to ensure RBI files (for Sorbet) are updated:

```shell
bin/tapioca gem
bin/rails db:migrate db:test:soft_reset; bin/tapioca dsl
```

([More details](https://thehub.github.com/epd/engineering/products-and-services/dotcom/development-environment/#from-git))

The gem contains several VCR recordings that are used by tests in gh/gh (via `persist_with: :turboscan`). These are kept up-to-date by our unit tests at `ts/cassettes/sessions`.

### VCR Cassettes

Our unit tests compare and re-record many of our VCR recordings using the latest Turboscan TWIRP endpoints.

They are distributed along-side our turboscan-client gem to be used in unit tests.

#### Altering a Twirp endpoint

If you are altering a Twirp endpoint run `make cassettes`, check the diff makes sense and then commit it. You then need to follow the gem vendoring instructions above and make sure
all the tests pass with the new version of turboscan-client and its cassettes.

#### Adding a new cassette

To add a new cassette, record it normally and then copy it from gh/gh into `ruby/spec/fixtures/vcr_cassettes/**`. Alternatively
you can stub it out by hand. The first time it is recorded over the unit tests will fill in any responses from the server.

Next, update `ts/cassettes/sessions/**` to `Record` your cassette in one of the existing unit tests, or create a new unit test
if you require a database state that is not currently represented. Once your cassette is being regenerated in an idempotent way you can vendor it into gh/gh and remove the original cassette from the gh/gh `test/fixtures/vcr_cassettes` directory.

#### Updating a cassette with additional calls

##### Starting from github/github

If you change the behaviour of github/github so that one of our pages makes additional Turboscan calls, the relevant cassettes will need updating. VCR will tell you this when you run tests, saying `An HTTP request has been made that VCR does not know how to handle`.

To update the cassette, follow these steps:

Add `record: :new_episodes` to the `use_cassette` call in your monolith test(s). They'll then look something like this:

```shell
VCR.use_cassette("code-scanning/show", persist_with: :turboscan, record: :new_episodes) do
```

This will in fact create a whole new copy of the cassette in `test/fixtures/vcr_cassettes/code-scanning/` which it will use in preference to the one in the gem. Don't commit this new cassette or the `record: :new_episodes` argument. Instead we will add the new request to the corresponding cassette generator in github/turboscan so that it will be automatically updated when the protobuf schema changes.

Note: Since tests that use cassettes don't rely on particular data being in your local Turboscan, you'll probably find that the result from the new request is something like 404. Don't worry about this; you'll update the response shortly.

To update Turboscan, start by diffing the updated cassette with the original from github/turboscan so that you can see what's new. Copy over any new request(s) to the relevant YAML file in Turboscan (don't copy the response). You may find that unnecessary headers are added to the request so they can be removed too - you only need `content/type: json`.

As part of this updating process, you'll need to change the IDs etc in the new request(s) to match those in the existing requests, otherwise re-recording will still get you a "not found".

Once you've updated the Turboscan YAML file, run `make cassettes` to re-record and get responses populated.

Finally, make a PR to update your cassettes in Turboscan and update the gem in github/github once it's merged. In the meantime, you can continue to use the new cassette(s) in `test/fixtures/vcr_cassettes/code-scanning/` to enable you to keep on running and developing tests in the monolith. Remember not to commit these cassettes, as they would then be used instead of the cassettes provided by Turboscan, which isn't what we want.

##### Starting from Turboscan

You may find that you know what additional requests you want to support in your cassette before you actually write any github/github code. In that case, you can begin by manually updating the cassettes in Turboscan, rather than diffing and copying as above.

### Updating the workflow template for default setup

See [documentation](ts/workflows/versions/README.md).

### Other folders worth noting

- `cmd`: where we define the `main` package files. Those are the entry point and tools for the project.
- `proto`: the .proto definitions. When changing any API, that's where you would change its definition and auto-generate new .go files under `ts/proto`.
- `schemas`: the MySQL table definitions used on dotcom (not GHES). See the
  [folder-specific README](schemas/README.md) for information on running migrations.
- `migrations`: the migration files used on GHES. There is [a test](https://github.com/github/turboscan/blob/3937465c0ab5a9e4cd71ce6ad9b3932999f7f092/ts/mysql/migrator_test.go#L93)
  that running these migrations in order yields the same database
  schema as the current state of the `schemas` directory.

See [additional documentation](docs/README.md).

## Production

*For details of Operational tasks and Observability, see the
[Code Scanning runbook](https://ops.githubapp.com/docs/playbooks/github/code-scanning/runbook.md), or read on for production-related tasks you might need as part of developing Turboscan.*

### Deploying a branch

We use the [Merge Queue](https://thehub.github.com/epd/engineering/devops/deployment/merge-queue/). TL;DR:

> press the "Merge when ready" button in a pull request

### Database transitions

(For details of migrations see [`schemas/README.md`](schemas/README.md).)

#### Creating a transition

Transitions (aka data migrations) should be created using `script/create-transition`.

The create-transition script will also add a call to `bin/migratorctl` in `script/db-migrate`.
This will run in development to keep development environments up to date and ensure that the transition is tested in
CI.

There are several types of transitions that are now supported. As a default
option please consider one of the batched transition types. Often this will be the `Batched` function from `ts/mysql/upgrades/batched.go`,
but there are other approaches available too - see the other files in that folder.

#### Running a transition

In order to run the transition, open a PR containing that code. This would
normally be the PR that introduces the transition, but does not have to be, for
example if you wish to re-run a transition. The PR serves as a permanent record
of the run. Full usage documentation is available on [the
Hub](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/#usage).

In the simplest case, note the transition's `name`, go to
`#dsp-code-scanning-ops` and use the chatop:

```text
.transitions run <PR url> * --transition <name>
```

The `*` will run on all stamps in the same order as deployments. You likely want
to start with a dry-run if possible, or by running on a small id range in either
Proxima or Dotcom, for example:

```text
.transitions run <PR url> production --transition <name> --minid 1 --maxid 10
```

While running a transition in production, keep an eye on the Code Scanning
dashboards to ensure that you are not negatively impacting the service, for
example by causing increased timeouts. If this does happen, you can use the
`-delay` flag to space out executions.

Hubot will also give you a link to logs in Splunk in its response to the chat-op.

### Sending a fake exception to Sentry

You can send an exception by sending a request to the `/_report` endpoint. This is useful if you want to test whether an exception makes it to Sentry or not:

```shell
curl --request "POST" --location "https://turboscan-production.service.iad.github.net/_report" --header "Content-Type:application/json" --header "Request-HMAC: $(gh-rpc ts hmac)" --data '{"err": "bad-example-error"}'
```

### Chatops

We have the following chatops

- `.ts ping` - Returns a "pong" response
- `.ts hmac` - Returns an HMAC token for production (valid for about 10 minutes)
- `.ts pprof` - Returns a pprof dump for a given profile. Please [refer to the pprof documentation](docs/pprof.md) for more details and how to use pprof.

Chat-ops can be triggered from Slack, or from an ops-shell using the `gh-rpc` command. e.g. `gh-rpc ts ping`.

#### Chatop development

New chatops can be added in `ts/chatops`. Make sure to register them in the `defaultChatops()` function and add a description in the [hubot-rpc-config](https://github.com/github/hubot-rpc-config/blob/main/rpc-endpoints/ts.yaml) repository.

When adding a new chatop, make sure to run `.rpc hup` in `#deploy-ops` to refresh Hubot's list of available chatops

## Sensitive Data

Because TurboScan ingests and stores SARIF data, all data that is part of the [SARIF specification](https://docs.oasis-open.org/sarif/sarif/v2.1.0/csprd01/sarif-v2.1.0-csprd01.html) may be handled by the application. In particular file paths and code snippets are sensitive and should not be logged by TurboScan.
