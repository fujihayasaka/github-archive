# Dependabot API

The API for Automated Security Updates and Scheduled Updates.

## Need to file an issue?

Internal issues should be filed in the `github/dependabot-updates` repo. [Start here](https://github.com/github/dependabot-updates/issues/new/choose).

## Setup

```bash
$ script/setup
```

## Codespaces setup

To [launch a Codespace](https://github.com/codespaces): select “New codespace" -> “github/dependabot-api”, then “Create codespace”.

That's it! You can verify things are working by running `script/test` to run the test suite.

## Working with dotcom locally

Get set up working with [dotcom locally](https://github.com/github/dependabot-updates/blob/main/docs/development/working-on-dotcom-features.md).

### Quickstart: Run with Codespace-Compose

Ensure that the `gh` tool and the `codespace-compose` extension is installed or upgraded to the latest version.
- To install `gh extension install github/gh-codespace-compose`
- To upgrade `gh extension upgrade gh-codespace-compose`

You must login to `gh` using a PAT that has full `codespace` permission, e.g. `gh auth login --with-token < PAT.txt`. The first time you run this, it will prompt you to authorize SSO to the GitHub organization, and then also authorize additional codespace access.

1. `gh codespace-compose up` to start a Codespace for each dotcom and Dependabot API. Leave this terminal running to forward ports from the Codespaces to your local machine.
2. In a new terminal window, run `gh codespace-compose ssh github` (or connect to the correct codespace with `gh cs ssh`)
   - In this window, run `env | grep DEPENDABOT` to verify the environment variables have been injected in `.bashrc`. If they are not run `source ~/.bashrc` until they are present.
   - Next run `script/server`. Leave this terminal running.
4. In a new terminal window, run `gh codespace-compose ssh dependabot-api`
   - In this window, check for `.env.local` to be present by running `ls .env.local` and then proceed.
   - Run `script/setup`. After a few minutes, the script should print that it connected to dotcom successfully.
   - Run `script/server`. Leave this terminal running after completion.
5. To run background jobs run `docker compose up consumer aqueduct-worker`
   in a terminal in the `dependabot-api` codespace. Leave this terminal running
   after completion. This will allow Dependabot to react to update enablement or
   edits to `dependabot.yml` or manifest files on dotcom.
6. Dotcom and Dependabot API are running now running and connected, and dotcom
   is forwarded to port 80 on your local machine. To verify functionality, view
   the Dependabot settings for a repository in stafftools. ([example local
   URL](http://github.localhost/stafftools/repositories/monalisa/illuminati/dependabot)).
   If dotcom and Dependabot API are connected, no error message will appear.

* To stop the Codespaces: `gh codespace-compose down`
* To restart stopped Codespaces: `gh codespace-compose up`
* To delete Codespaces: `gh codespace-compose rm`
* If experiencing errors re-provisioning after the Codespaces have been deleted
  (such as can happen when deleting from the UI), delete the
  `.codespace-compose.yml.lock` file and retry.

**Note for non-bash shells:** Invoke scripts with `bash -lc script/server`.
Necessary environment variables are added to bashrc during Codespace-Compose
provisioning, so a bash login shell (`-l` option) must be used to start
scripts.

## Development

All development happens in docker containers.

To run the application locally:

```bash
$ script/server
```

To start the Rails console:

```bash
$ script/console
```

To run the test suite:

```bash
$ script/test
```

To update after pulling remote changes:

```bash
$ script/update
```

## Onboarding a New Ecosystem

Dependabot API includes an automation tool to streamline the process of adding a new package ecosystem. The tool automatically updates all necessary files including protobuf definitions, feature flags, config parsing, and schema files.

### Usage

```bash
rake ecosystem:onboard[ecosystem_name,package_manager_name,mode]
```

**Parameters:**
- `ecosystem_name` (required): The ecosystem name as it appears in config files (e.g., 'conda', 'uv')
- `package_manager_name` (optional): Package manager name if different from ecosystem (defaults to ecosystem_name)
- `mode` (optional): `interactive` (default), `skip`, or `overwrite`

**Examples:**
```bash
# Interactive mode (prompts for each change)
rake ecosystem:onboard[conda]

# Overwrite mode (no prompts)
rake ecosystem:onboard[uv,,overwrite]

# Skip mode (dry-run)
rake ecosystem:onboard[helm,,skip]
```

After running the tool, you'll need to:
1. Update file patterns in `lib/ecosystem_file_regex.rb`
2. Run `script/protoc` to regenerate protobuf code if needed
3. Add language/advisorydb mappings in `lib/ecosystems.rb`
4. Run tests and update documentation

For detailed documentation, see [docs/ecosystem-onboarding.md](docs/ecosystem-onboarding.md).

### Running a Consumer

We maintain a small fleet of [Hydro](https://github.com/github/hydro) consumers
in order to ingest events from the GitHub monolith in production.

When working locally, you may need to run a consumer to test your work. You can
do this via the following command:

```shell
docker compose run worker script/hydro-consumer MyEventProcessor
```

This script can be used to run any `ApplicationProcessor`-derived class in
app/processors.

#### Consuming Alerts

Consuming Repository Alert-related events requires some addition configuration
due to technical debt around their implementation.

To consume events generated by clicking the "Resolve" button on the alert page:

```shell
docker compose run worker script/hydro-consumer VulnerabilityAlertProcessor \
                                                -s github.v1.RepositoryVulnerabilityAlertResolveRequest \
                                                -g vulnerability_alert_resolve_request_relay
```

To consume events generated by manifest pushes/enabling Dependabot/an alert
being published:

```shell
docker compose run worker script/hydro-consumer VulnerabilityAlertProcessor \
                                                -s github.v1.RepositoryVulnerabilityAlertCreate \
                                                -g vulnerability_alert_relay
```

### Using the GitHub Advisory Database in Development

Dependabot API uses the [GitHub Advisory service](https://github.com/advisories)
to determine which Dependency versions are vulnerable when performing upgrades.

In Production, we request these Advisories from dotcom via the Twirp protobuf API.

In development, you may seed this data on development dotcom via `bin/seed global_advisories`.

In your dotcom instance console you can inspect the seeded advisories with `Vulnerability.disclosed` and `Vulnerability.disclosed.first.vulnerable_version_ranges`

### Using kredz
[kredz](https://github.com/github/kredz) is a service owned by the actions team
which we use to encrypt update job credentials. To run/test it locally you can
perform the following step in the dotcom instance of the codespace-compose environment:

```bash
start-actions
```

### Installing new gems

To bundle new gems after modifying your Gemfile:

```bash
script/update-gems
```

The script will guide you through the necessary steps to bundle gems from
[octofactory](https://github.com/github/octofactory).

### Tracing

We rely on [`github-telemetry-ruby`](https://github.com/github/github-telemetry-ruby) for emitting OTel data
and [Lightstep](https://app.lightstep.com/github-prod/project) for collecting and analyzing this data.

If either the `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` or `OTEL_EXPORTER_OTLP_TRACES_HEADERS` environment variables
are present when the application boots, the global tracer will attempt to export tracing data to the configured
endpoint. By default these environment variables are undefined in development. To export tracing data during
development,
[start a local Lightstep developer satellite](https://thehub.github.com/epd/engineering/dev-practicals/observability/distributed-tracing/lightstep-development-mode/)
and uncomment the environment variables in your
`.env.local` file.

### Linting

We use [rubocop](https://github.com/rubocop-hq/rubocop) to lint our code using community-agreed defaults.

You can run this locally:

```shell
script/lint
```

We expect this build to succeed as a requirement for merging PRs.

#### Tracking Linter TODOs

We aim to configure our linter to be as close to default as possible, but occasionally it isn't efficient to solve
wide-spread problems in a single PR.

Rather than treat rules as binary that must pass everywhere or be disabled, we use Rubocop to automatically generate
a `rubocop_todo.yml` file to disable rules on a per-file basis.

We have generated this file using this command:

```shell
script/app-env bundle exec rubocop --auto-gen-config --exclude-limit 99999
```

By default, Rubocop will disable a rule that has more than 15 files excluded. We set this to an excessively high value
using `--exclude-limit` to avoid this behaviour. This ensures we will not silently ignore problems being introduced to
new files.

#### Resolving Linter TODOs

The `.rubocop_todo.yml` is a starting point when looking for files to improve. You can also run a strict linter
build that skips the todo file:

```shell
script/lint --strict
```

This will output an ordered list of the worst offenders by linter rule.

We run the strict build in CI and will fail it if the total offences changes. This ensures we notice when the code
gets worse but it does not block merges.

#### Updating Lint rules

Our first preference is to fix new offences when they are highlighted by a CI failure.

If this isn't practical, the best practice depends on whether it is a new violation of an existing rule or a newly
introduced rule.

- New violations of _existing rules_ should use `rubocop:disable` comments around the offending code
- Newly introduced rules should regenerate our todo file to capture the current state in one place

The todo file can be regenerated like so:

```shell
script/lint --regenerate-todo
```

This command will use the same configuration settings as the existing file.

## Testing

We use RSpec with FactoryBot. Run the tests with `script/test`.

You can also run a single test:

```shell
script/test spec/models/foo_spec.rb:10
```

Some fixtures are recorded with VCR. To re-record them, set the
`DEPENDABOT_TEST_ACCESS_TOKEN` environment variable to a working GitHub access
token, and run the tests with `VCR=all`.

```shell
script/app-env VCR=all DEPENDABOT_TEST_ACCESS_TOKEN=<redacted> bundle exec rspec spec
```

## Production

To access the dependabot-api rails console [follow these instructions](https://github.com/github/dependabot-updates/blob/main/docs/production-shell-access.md)

To get a console to the dependabot-api(Moda app) launch a `kubectl` ephemeral shell. Follow [these setup
instructions](https://thehub.github.com/security/security-operations/production-shell-access/shell/)
for ephemeral shell access prior to the steps below.

Vault login:

```bash
$ . vault-login
```

In the shell machine run:

```bash
$ gh-kubeconfig general-1-ash1-iad
$ gh-k8s-shell -n dependabot-api-production -- bash
```

To troubleshoot, you can also consider following these steps as an alternative:

Find the namespace to troubleshoot:

```bash
kubectl config get-contexts
CURRENT   NAME                          CLUSTER                       AUTHINFO                                NAMESPACE

*         proxima-1-staff-wus2-01-az1   proxima-1-staff-wus2-01-az1   proxima-1-staff-wus2-01-az1-kubelogin
          proxima-1-staff-wus2-01-az2   proxima-1-staff-wus2-01-az2   proxima-1-staff-wus2-01-az2-kubelogin
          proxima-1-staff-wus2-01-az3   proxima-1-staff-wus2-01-az3   proxima-1-staff-wus2-01-az3-kubelogin
          ....
          ....
```

Get all the pods in the corresponding namespace:

```bash
kubectl get pods -n dependabot-api-staff-wus2-01
NAME                                                              READY   STATUS             RESTARTS        AGE
api-855c444574-rsf6z                                              0/1     CrashLoopBackOff   7 (2m10s ago)   14m
api-bdb6b6c9c-8mftb                                               1/1     Running            0               3h34m
aqueduct-resqued-worker-547d5db8c9-5xb7g                          1/1     Running            0               19m
....
....
```

Get the pod logs in the corresponding namespace:

```bash
kubectl logs <pod name>  -n <namespace>

Example:
kubectl logs api-855c444574-rsf6z  -n dependabot-api-staff-wus2-01
```

In case the pod has crashed, you could perform a rollout of the deployment in the corresponding namespace to obtain a new pod swiftly,
allowing you to examine its logs:

```bash
kubectl rollout restart deployment -n dependabot-api-staff-wus2-01
kubectl get pods -n dependabot-api-staff-wus2-01
kubectl logs <pod name>  -n <namespace>
```

## Deploying Dependabot-api to Production

1. Make the changes and submit a PR to the dependabot-api repository.
2. Get the PR's approval. Hold off until all of the test cases for the PR pass.
3. Enqueue your PR into a merge queue. You can do this by clicking "Merge when ready" on the PR or by issuing the chatops below. Please refer to the [Merge Queue docs](https://thehub.github.com/epd/engineering/devops/deployment/merge-queue/) on TheHub for usage details.

```shell
# in #dependabot-deployment-ops
.queue me to deploy <PR url>
OR
.qmtd <PR url>

Example:
.qmtd https://github.com/github/dependabot-api/pull/3037
```

4. You will be notified of the deployment's progress in the Slack channel [#dependabot-deployment-ops](https://github.slack.com/archives/C04N707KJUS), and can be viewed by clicking on the links marked with a red box.
<img width="618" alt="Screen Shot 2022-08-05 at 10 31 06 AM" src="https://user-images.githubusercontent.com/5500812/183133499-0ddd91ac-4d93-4a11-a16e-06b45aab2600.png">

5. Observe metrics and issues for the deployment.
   1. The [Datadog deployment confidence dashboard](https://app.datadoghq.com/dashboard/mzk-f93-u7m/dependabot-deployment-confidence?live=true) should be stable and consistent through the deployment.  There will be a deployment spike for the `Unavailable containers` chart during the deployment of the dependabot-api, and shortly after the successful deployment the spike should go down to 0.
   <img width="492" alt="Screen Shot 2022-08-05 at 10 32 46 AM" src="https://user-images.githubusercontent.com/5500812/183131773-43ffc1ae-1059-4554-aa68-1c10fd23ffb9.png">

   2. Find the [Sentry release](https://github.sentry.io/releases/?project=1861010&statsPeriod=1h) matching the deployment SHA and watch for any new issues, regressions, or increase in issue rates.

7. These steps will repeat for each environment to which dependabot-api is deployed

8. The pull request should automatically merge when the deploy completes

### Deploying Manually

If you need to deploy manually (ex. needing to bypass additional builds in an emergency), you can do so with the `.deploy` chatop. You must specify the environment to which you are deploying and flag that you are ignoring required pipeline deploy.

```shell
# in #dependabot-deployment-ops
.deploy https://github.com/github/dependabot-api/pull/3037 to production --ignore-required-pipeline
```

## Database Migrations

Dependabot API uses [github/skeefree](https://github.com/github/skeefree) to
perform automated migrations to our production database cluster.

This means our process of generating migrations is a little bit different to
a base line Rails application.

### Generate your migration

```shell
script/generate-migration add_index_on_github_login_to_accounts
```

### Apply your migration

Edit the generated migration file as normal. If adding a table specify a
charset and collation (`charset: "utf8mb4", collation: "utf8mb4_general_ci"`)
so we'll have consistent settings on GHES which has different defaults. When
finished, apply it to your local schema:

```shell
script/migrate
```

In addition to updating the `db/structure.sql` as normal, this will also update
the relevant `.sql` files in `schema/deltaforce_production`.

These files are used by skeefree to generate a set of queries for
[database-infrastructure](https://github.com/github/database-infrastructure) to
review and run for via their automation.

### Open a PR

Push a branch with just your new `db/migrate/` file and the generated diffs to
`db/structure.sql` and `schema/*`.

The [skeema-diff-gh](https://github.com/github/github/actions?query=workflow%3Askeema-diff-gh)
action will detect your changes and apply the appropriate labels.

From there, just follow Hubot's instructions to mark your change for review and
Hubot will tell you when the migration has been carried out and you are ready
to merge your diff :sparkles:

### Rolling back

In the event you need to revert your migration locally, please use the helper
script:

```shell
script/rollback
```

This will make sure the `schema/` folder changes are reset for you.

## Exception Handling

Dependabot API uses [Sentry](https://sentry.io/organizations/github/projects/dependabot-api/?project=1861010&statsPeriod=24h)
to monitor errors. This is a third-party service, so we **must** carefully observe
the [secure exception handling guidelines](https://thehub.github.com/epd/engineering/development-and-ops/observability/exception-tracking/secure-exceptions).

Dependabot primarily handles User Repository Data which has many restricted or confidential attributes.
When creating or monitoring exceptions, please pay special attention to Repository data. If in doubt, raise the
issue with the team and follow the [breach remediation guidelines](https://thehub.github.com/epd/engineering/development-and-ops/observability/exception-tracking/secure-exceptions/#breach-remediation)
if necessary.

## Further Documentation

For more topics on the care and feeding of Dependabot, go [here](https://github.com/github/dependabot-updates/tree/main/docs).
