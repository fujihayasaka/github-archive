# Database Migrations and Transitions

## Important!

We've noticed that our chatop to cancel a transition doesn't always work (e.g. `.deploy cancel launch in backfills`). 
There are 2 other options to cancel an ongoing transaction:
- If `launch/master` has transitions turned off (through having an `echo` command in [transition.yaml](../config/kubernetes/backfills/jobs/transition.yaml)), then you can run `.deploy launch/master to backfills` to override the current transition.
- Delete the `launch-transitions` job in the `launch-backfills` environment. See [k8s tips and tricks](./kubernetes-tips-and-tricks.md) for how to do this.

## Setup

You need `golang-migrate` installed and first in your $PATH (the binary name `migrate` conflicts with another one we also use).
On macOS, you can use `brew install golang-migrate` to install. In a Linux environment like Codespaces, use `script/install-golang-migrate`.
Validate with `where migrate` that the correct program is first in your `$PATH`.

If it is not configured properly, you'll see errors like `Could not load .env file prior to running migrations.` or `Access denied for user`. If `migrate -version` complains about `Incorrect Usage`, it's the wrong `migrate` binary.

## Creating a migration

1. Create a new database migration by running `script/create-migration <deployer|actions_workflow_payloads> <migration name>`
2. Fill in the newly created migration files, making sure to make both an `up` and `down` migration.
3. After doing that, take the timestamp from the first part of the file and add any data transitions necessary in `cmd/migratorctl/transitions.go` for the relevant database table.
4. Run `script/migrate-mysql` to apply these migrations and also update the `skeema` SQL files.
5. Push up your changes to a new branch.

To get a mysql console to your launch dev database, run `script/dbconsole`.

If you need to iterate on your migration, you can rollback in development:
`script/migrate-deployer down 1`
`script/skeema pull --ignore-schema ".*_test|launch_development|test_*"`

To force rollback to a previous version: `script/migrate-(deployer|payloads) force <timestamp>` e.g. `script/migrate-deployer force 20220121182213`

If all else fails, wipe the DB container volume. This will also rebuild the schema files:
```
script/docker-compose down -v
script/start-db
script/sql-grant-access
script/migrate-mysql-setup
script/migrate-mysql
```

If dropping a table or column, ensure that the database table / column is not being used within [airflow](https://github.com/github/airflow-sources/blob/master/dags/db_snapshots/configs/vitess/launch/launch-daily.yaml). If it is, open a PR to drop it.

## Creating a transition
For those new to transitions, or wanting more context on what they are and how they're used at GitHub, see: https://github.com/github/engineering/discussions/2589

For transitions to run in Enterprise (GHES), there needs to be a matching migration with the same version timestamp. You can skip several steps below if your transition only needs to run in the hosted environment (i.e. github.com).

> **Note**: Before proceeding, ensure your local dev environment is [setup appropriately](./local-dev.md#local-development).

1. Run `.wcid launch` and check if there's a `backfills` environment. Restore the `backfills` environment if necessary. Example [PR](https://github.com/github/launch/pull/4955)
1. **Hosted + Enterprise transitions**: Create a new, empty database migration by running `script/create-migration <deployer|actions_workflow_payloads> <transition name>`. You can add `SELECT NOW();` to the `up` and `down` scripts.
    - You can skip this step for hosted-only transitions.
1. Create a transition under `/cmd/migratorctl/transitions`.
    - See [this transition](../cmd/migratorctl/transitions/transition20200409104519/backfill-checkout-sha-ref.go) for an example. If your transition is meant to archive a tenant mapping, check out the [**Archiving Tenants**](#archiving-tenants) section further below, then come back to this part of the document.
    - Make sure you implement `GetTransition`!
    - Version timestamp guidance:
       - Hosted + Enterprise transitions: Use the same version timestamp as your empty migration (see Step 2).
       - Hosted-only transitions: You can use `date +"%Y%m%d%H%M%S"` to create a version timestamp in the correct format.
       - When you merge in changes from master, you may need to bump the version timestamp of your transition (and empty migration) to keep your transition the latest. The job that runs in the `backfills` environment runs the latest transition by version timestamp.
1. Register your transition in [transitions.go](../cmd/migratorctl/transitions.go).
1. Test your transition locally

    - Ensure you build your transition and any changes with `script/build` before running `script/run-transition`. If you're running a transition to archive a tenant, check out the **Archiving Tenants** section further below, then come back to this part.
    - To run a single transition, you can use the `script/run-transition` command, for example: `script/run-transition deployer 20220322142609`
    - If your transition doesn't run in Codespaces, you may need to unset the `CODESPACES` environment variable before testing it, ex: `CODESPACES=false script/run-transition deployer 20220322142609`

1. Open a PR with your changes.
1. Check that [transition.yaml](../config/kubernetes/backfills/jobs/transition.yaml) in the PR is set up to run the transition. ([commit example](https://github.com/github/launch/pull/5771/commits/bc1eb5cba81ee5d263d86c39082da8f69053a215))

    - Make sure that `IS_DRY_RUN` is set accordingly
    - Remove `echo` from commands to allow transition to run

1. Deploy transition to backfills (`.deploy <pull_request_url> to backfills`).
    - This will automatically run your transitions as a job. Follow the progress [on Moda](https://moda.githubapp.com/apps/launch).
    - Track the transition errors and velocity separately on a dashboard. Example [dashboard](https://app.datadoghq.com/dashboard/h3t-2d8-kxa/actions-experience-global-id-reaction?from_ts=1651779784017&to_ts=1651783384017&live=true) for the globalID transitions.
    - It may report back saying that the deployment failed, but it is likely that the transition still ran. You can confirm with [`gh-dbconsole`](https://github.com/github/c2c-actions/blob/39bc378b779aab5f5f01e1ce3b75220bd2240081/docs/production-database-access.md#gh-dbconsole).
        - Run `.unlock launch in backfills` afterwards if the transition ran successfully.
1. **Hosted-only transitions**: Close your PR without merging. You're done! 🍦 The steps below don't apply.
1.  Revert changes in [transition.yaml](../config/kubernetes/backfills/jobs/transition.yaml) so that transitions don't run on future deploys
1.  Ensure the [Migration Ordering Check CI](https://github.com/github/launch/actions/workflows/migration-ordering-check.yml) is passing for your empty migration. Bump the version timestamp of your empty migration and transition if necessary.
    - You can use `date +"%Y%m%d%H%M%S"` to create a new timestamp in the correct format.
1. Deploy your PR to production.
1. Merge your PR.

## GHES considerations:

In the launch production environment, migrations run independently of transitions (via skeefree and backfills respectively). In GHES however, they are [both run together](https://github.com/github/enterprise2/blob/183dc96e3ee56bfce572aa3e6782544ce2c27974/vm_files/usr/local/share/enterprise/ghe-run-migrations#L103-L105) as part of the command `migratorctl migrate <service> -d "$DATABASE_URL" -s migrations/<service>`. We need to write transitions accounting for what will happen if they fail. They should be written to be idempotent, so that they can be rerun without consequences. If there is any optimization that can be done to make them run faster on a rerun, that may be helpful to add (for example - ensuring the migration adds an index that can then be read from to calculate what rows need to be iterated over, or even caching the value [as done here](https://github.com/github/launch/blob/1b85bc905a858984b56edde539263d97d8963d66/cmd/migratorctl/transitions/transition20220207140551/backfill-credentials.go#L134-L135))

## Re-usable transitions for production

We have transitions for the production environment (github.com) that can be tweaked and re-run as necessary. A transition may be preferable to a chatop when there are large number of arguments or you want the change approved by a launch reviewer. These transitions are not intended for Enterprise (GHES) and should not be merged.

### Archiving Tenants
[#5432](https://github.com/github/launch/pull/5432) can be used to archive specific production tenants. To use it, you'll need to know the global `entity_id` associated with a given tenant ID, which you can find by making a `data.githubapp.com` query [like so](https://data.githubapp.com/sql/share/02899fdf). Alternatively, if you know the `nwo` associated with the tenant ID, which you likely will if this is in response to a customer support ticket, you can look up that `nwo` in Stafftools, then navigate to Admin > Database and grab the value of `next_global_id`. From there, you can use the template linked above (plus or minus small modifications) to create a transition PR that will archive the tenant. Here's a more recent example that was initially based on the template PR: https://github.com/github/launch/pull/6278/.

To more thoroughly test out your archive transition in the `github/github` environment, after starting actions using [these](https://github.com/github/c2c-actions/blob/main/docs/actions-development.md#bootstrap-actions-) steps, add a folder to the workspace that includes `launch`. From there, navigate to the `launch` directory, checkout your branch which includes the transition code, and run `script/dbconsole deployer` to open mysql. Next, invoke `select entity_id, environment from azp_resources;` to get a listing of current `entity_id`s available in the dev environment. You may see an output similar to:
```
launch_deployer_development> select entity_id, environment from azp_resources;
+-----------+-------------+
| entity_id | environment |
+-----------+-------------+
| E_kgAB    | development |
| O_kgAE    | development |
+-----------+-------------+
2 rows in set (0.00 sec)
```

Next, privately modify your transition code to target one of these IDs, and rebuild using `script/build`. Then, run your modified transition. If successful, and you targeted `O_kgAE` for instance, you should see an output like the following when you requery `launch_deployer_development`:
```
launch_deployer_development> select entity_id, environment from azp_resources;
+-----------+--------------------------------+
| entity_id | environment                    |
+-----------+--------------------------------+
| E_kgAB    | development                    |
| O_kgAE    | development-deleted-1674527878 |  <--- Note that the environment is now marked as deleted here!
+-----------+--------------------------------+
2 rows in set (0.00 sec)
```
After this, don't forget to undo the temporary testing changes you made so that your actual PR will target the right tenant!
