# Advisory DB

Advisory DB is an API-only application responsible for:

- [importing](docs/import.md) information from security feeds
- resolving that information into reviewable advisories
- managing the security advisory [curation](docs/curation.md) process
- publishing reviewed/accepted global advisories to dotcom & advisories repo

as well as:

- receiving CVE requests for repository advisories
- reporting assignment decisions back to maintainers
- managing the CVE curation process
- setting up PRs to publish CVEs to MITRE's CVEList repo

## Curation

Curation takes place in the [Advisory Inbox app](https://advisory-inbox.githubapp.com).

### Chatops

There is a set of chat ops that are used to augment the curation process.
All chatops live within the `.ghsa` command, try `.ghsa` in slack to see a help doc with all commands.

## Development

All development happens in docker containers. Once you're set up, things like
`bin/rake` and `bin/rails` should work transparently along with `script/server`
and `script/test`.

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

### CVE Services Dev API

You can also run, at the same time, the development version of the CVE Services API to test our integration with their application. Run the following command in a separate, additional terminal session:

```
docker-compose up cve_services
```

Populate the database with:

```
docker-compose exec cve_services npm run populate:dev
```

### Getting Started

*Certain environment variables need to be set in order for the scripts to work. The following script generates the file `.env.local` out of the `.env.local.example`. If you don't need a full end-to-end setup, you can assign dummy values to the variables there. Otherwise, follow the next section to obtain the proper values.*

First, install the Docker app using Homebrew:
```bash
brew install --cask docker
```
ghcr.io containers require Docker to be logged in to download.

Setup a [classic personal access token with read/write/delete packages permissions](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#authenticating-with-a-personal-access-token-classic) AND enable SSO on the token for the `github` organization. 

Setting the token expiration over 90 days will violate a GitHub security control, so set it for something lower or be prepared to get yelled at.

Once you have your token, authenticate Docker with the following:

```bash
$ echo "ghp_someLETTERSandNUMBERS" | docker login ghcr.io -u USERNAME --password-stdin
```
Assuming you get

```
> Login Succeeded
```
then, just run

```bash
$ script/setup
```

…and you're off to the races!

### Development Data

There is some basic seed data for development which can be created using:

```bash
$  bin/rake db:development_data
```

When the development data does not meet a certain need in development, extending the data is the best thing to do.

It is also currently possible to use production data locally ([docs](https://github.com/github/advisory-db/blob/c518158e50b549bb7028d51366486029c2cd6398/docs/load_production_data_locally.md)) and that can be a good way to get a large DB if that is needed, or if really realistic data is needed for another reason.

### Complete local development setup with advisories and cvelist repos

#### Developer GitHub App

- Create a private repo in your regular GitHub staff account called `advisories-test` or similar.
  - Include a README so there is an initial commit.
  - Change the default branch to `main` if it is created as `master`
- Create a private repo in your regular GitHub staff account called `cvelist-test` or similar.
  - Include a README so there is an initial commit.
  - Change the default branch to `master` if it is created as `main`
- Create an app: https://github.com/settings/apps/new, call it `{username}-advisory-db-test` or similar, where {username} is your login to make the app name unique.
  - Fill in the Homepage URL with something such as your advisories repository url: `https://github.com/{username}/advisories-test`
  - For now, set the webhook url to some dummy value like `http://example.com/webhook`, we'll come back to that
  - Give app the following repository permissions:
    - Checks: Read & write
    - Contents: Read & write
    - Metadata: Read only
    - Pull requests: Read & write
  - Subscribe app to following events:
    - Check run
    - Check suite
    - Pull request
  - Make sure for `Where can this GitHub App be installed?` that the `Only on this account` is selected. This app should not be made public
- Configure the app:
  - Note the App ID. Such information will be used later for `.env.local`
  - Set the Webhook Secret and click `Save changes`
  - Under Private keys, click to `Generate a private key`. A `.pem` file will be downloaded. The content of this file will be used later to set an environment variable.
- Install the App into the advisories and cvelist repos, get the installation ID, keep that for `.env.local`
  - To get the installation ID, Visit `/settings/apps/<your-app-name-here>/installations`, click the wheel icon on your installation and pull the ID from the URL.
    - An alternate method for getting the installation ID to use [`bin/get-integration-access-token`](https://github.com/github/github/blob/master/script/get-integration-access-token).
    - Put the private key into a file, and run the command like so: `./bin/get-integration-access-token -k ~/.ssh/advisory_db_test_rsa -a 40232 -v`, and note in the output that the first query it does is to get the list of installations, the first one returned is your installation ID.
- Setup environment variables in `.env.local`:
  - Start by copying from `.env.local.example` , then filling in all the fields with IDs and Keys gotten above

#### Starting the Local Server

- Make sure the local environment is totally clean (*optional)
  - `docker-compose down --remove-orphans`
  - `bin/rake db:reset`
- Start the local server: `script/server` and tail the log
- Start ngrok `ngrok http 3000`, get the "Forward" url, will look something like: `http://2256ee9e.ngrok.io`
  - Note that this should be happening in a terminal on your local computer, not in a codespace
  - Install ngrok with `brew install --cask ngrok` if missing
- Put the forwarding URL as the webhook URL in the App above, appended with `/webhook`.  It should look like `http://2256ee9e.ngrok.io/webhook`.
  - Make sure to check `Active` to enable the webhook deliveries.
- Configuration is complete, and should be ready to use and work!  Going forward, all you should need to repeat is starting ngrok and configuring the webhook url in the app.
- Lets try it out
  - Edit the README in your advisories repo and watch the server log respond to the webhook


### Hydro schema

Advisory DB makes use of [Hydro](https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/).

In order to update the vendor'd copy of the schema one must run a command from the hydro-schemas repo:
`script/generate --ruby-out <path to this advisory db repo>/vendor proto/hydro/schemas/advisory_db`

:exclamation: You must replace `<path to this advisory db repo>` in the above command with a path to this repo.


#### Please note:

1. When you add or update a gem, first run `bin/bundle` to cache the gem locally, then run
   `script/bootstrap` to rebuild the docker container with the updated gems.
2. If you ever need to add an environment variable, you can add it to the
   `environments` list in `docker-compose.yml` and it will pass through
   transparently.

## Scheduled Tasks

We have several data ingestion tasks we need to perform regularly via a task
scheduler.

We make use of the [Kubernetes CronJob](https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/)
controller provided under [Moda](https://pages.ghe.io/moda/docs/) to run these.

Consult the manifests in `config/kubernetes/default/cronjobs` for examples when
adding more tasks.

#### Things to consider when adding a new task:

1. Is it idempotent?
  - By default a failed task will be retried, consider how your code handles
    being re-executed.
2. Does it fail loudly?
  - The most dangerous aspect of cron workflows is silent failures that can go
    unnoticed for long periods of time, especially if they run infrequently.
  - When testing, make sure errors appear in Sentry and consider adding
    instrumentation to make your job more visible.
  - Consider alerting if it is a mission-critical workflow.
3. Could it degrade service performance?
  - One of our main scheduled workflows is data ingestion, meaning a large
    number of inserts/updates, which could impact the database performance for
    API users.
  - Consider running your task manually before putting it on a schedule to
    profile it.

## Deployment

Deployment is performed via chatops in the [#advisory-db-ops](https://github.slack.com/messages/C9V8P10RY)
channel or using the Merge Queue.

- Push your branch, open a pull request, make sure it's up-to-date with master and the build is green.
- If you need to verify your changes on staging first, deploy with: `.deploy <pull-request-url> to staging`
- Go to the staging [site](https://advisory-inbox-staging.githubapp.com/) and poke around, sanity checking that things look good.
- Deploy to production using the `Merge when ready` button on your PR, this triggers a Heaven deploy pipeline.
- When the pipeline has completed its deploy, there is a 5 minute timer gate for you to verify your changes:
  - Watch for exceptions in [Sentry](https://sentry.io/organizations/github/issues/?project=1864109)
  - Watch the [main Datadog dashboard](https://app.datadoghq.com/dashboard/v8r-xt4-tpg/advisory-db) too for any relevant metrics
  - Go to the [app](https://advisory-inbox.githubapp.com) and poke around, sanity checking that things look good
- Unless you rollback the pipeline during this timer gate, it will automatically merge your PR

#### Migrations

Migrations for AdvisoryDB work a bit different than they do for dotcom.

Migrations are done per the [process established by database-infrastructure team](https://github.com/github/database-infrastructure/blob/master/docs/help/mysql/schema-changes.md).

Specifically for AdvisoryDB, the process goes approximately as follows:

1. Make a normal rails migration: `rails g migration MyMigrationName`
1. Make a PR with the migration, the database team would like us to put the migration in a separate PR in all repos [for clarity](https://thehub.github.com/epd/engineering/products-and-services/dotcom/migrations-and-transitions/database-migrations-for-dotcom/#things-that-are-not-allowed-).
1. The skeema-diff action should run and recognize this PR changes the db schema, and it should add a comment to the PR noting the skeema:diff output.  Confirm that skeema diff is correctly prescribing sql to make the required schema changes.
1. Get the PR approved by teammates before moving the PR further along the migration workflow.
1. Add the `migration:for:review` label once the PR is approved by AdvisoryDB.  This moves the PR into the DB Schema review queue for the database team.
1. Deal with any feedback from the DB team, get the PR approved by DB team.
1. Wait for comment from DB team noting the schema change SQL was correctly applied Once that is done:
1. On the console, add the row to schema_migrations table noting the migration was run. Note that this must be done manually and separately from then migration itself for reasons.  The DB team handles schema changes, and the application owner handles data changes.  The row in schema_migrations needed by Rails apps is technically a data change, so... do something like this (changing the version to match your migration): `ActiveRecord::SchemaMigration.new(version: "20190604224538").save`.
1. Merge/deploy the PR with the rails migration in it
1. Make sure everything working as expected.
1. All done!


#### Accessing the production console

1. SSH into the bastion host:
   ```
   $ ssh -A bastion.githubapp.com
   ```
1. From bastion, SSH into an ops-shell host:
   ```
   $ ssh -A shell.service.cp1-iad.github.net
   ```
1. From the ops-shell host…
   ```
   $ . vault-login # Note the "."
   $ kubelogin config general-2-ac4-iad
   $ gh-k8s-shell -n advisory-db-production script/console
   ```
1. Watch for exceptions in [Haystack](https://haystack.githubapp.com/advisory-db/firehose).
1. When you're confident that the deployment and migration were successful,
   merge your pull request and delete the branch.

More development tips are in the docs folder.


#### Accessing production logs

1. Within the [deployments section site for our app](https://moda.githubapp.com/apps/advisory-db/deployments/production?cluster=general-2-ac4-iad) in the moda site, click on "Running" for the pod you're interested in, and then it should prompt you to see some tailed logs
2. Look up [index=catchall kube_namespace=advisory-db-production kube_cluster=general-2-ac4-iad](https://splunk.githubapp.com/en-US/app/gh_reference_app/search?q=search%20index%3Dcatchall%20kube_namespace%3Dadvisory-db-production%20kube_cluster%3Dgeneral-2-ac4-iad&earliest=-15m&latest=now&sid=1639598090.10575_5FB4AC8E-DC1F-4236-99DC-C6032DC30760&display.page.search.mode=fast&dispatch.sample_ratio=1) in Splunk.

#### Experimenting with lightstep?
Check out https://github.com/github/github-telemetry-ruby#in-development to see the export requirements to enable using a lightstep developer satellite.

#### Fast dev loop

> [!NOTE]
> * You want to use fast dev loop if you don't want to wait for docker when developing
> * See what it changes by searching for the env var: FAST_DEV_LOOP
> * There could be side effects if you do both fast dev + normal docker in the same codespace
> * The biggest source of surprise is usually related to the database connection (making sure the fast dev loop has access) because there is a default instance of mysql that runs with the codespace due to our base image. We're setup to point to a *different* instance locally, hosted by docker-compose, and with a different port
> * There is some degradation in certain commands, like running script/lint will always have the same couple of tests fail due to docker hosted assumptions, but you can get a feel for this pretty easily
> * I found this useful enough that I pretty much always used it in my personal dev flow unless changing something with how we build via docker

You should be able to run the following steps from a new codespace.

1. Start the subset of sideloaded services (make sure to do this in a long running console that you let run separately) via:
`docker-compose -f docker-compose.fast-dev.yml up`
1. You will need to do `FAST_DEV_LOOP=1 bin/rake db:create db:schema:load db:migrate db:test:prepare`

This is a work in progress, but currently you can either export FAST_DEV_LOOP=1 or run scripts like `FAST_DEV_LOOP=1 script/server` to skip docker container composition for local dev. Some scripts may not support the variable yet, but it should be easy to add if you find it not supported. Search for uses of this variable in the codebase to better understand behavior.
