# Schemas

## Table requirements

All tables must have an auto-incremented primary key of the form:

``` sql
`id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
PRIMARY KEY (`id`)
```

A new table will usually contain a `repository_id` column unless you know that it will never be
sharded (e.g: data shared across all repositories).

Some of the tables are exported to the data warehouse using [airflow
definitions](https://github.com/github/airflow-sources/blob/master/dags/db_snapshots/config.py) (search for `TURBO_SCAN`). If you change one of these
tables, open a PR to update the corresponding airflow definition.

You can query the snapshots at https://data.githubapp.com/.

## Local migrations

Skeema is the tool we use to run migrations locally.
When wanting to change the database schema, you should go to the `schemas` folder and change the .sql file corresponding to the table you want to alter. For more info check the skeema repo: https://github.com/skeema/skeema
When adding a new migration, or if `git pull` adds other new
migrations to your working copy, you can run `script/db-migrate` to apply the migrations locally. `script/setup` will also apply the migrations for you.

While `db-migrate` should often get you what you need, sometimes you might want to start afresh with an empty db. To do that run:

```shell
docker compose down && docker volume rm turboscan_db-data && ./script/setup
```

## GHES migrations

Except in very unusual circumstances, the database schema for GHES should be kept in-step with that for dotcom. Therefore, you need to create a GHES migration alongside the dotcom one:

1. Make the desired change in the `schemas` directory.
2. _Before_ running `script/db-migrate`, run `script/create-migration <name>`.
    - Note that `script/db-migrate` runs automatically with `script/setup` and `script/server`. If the changes have already been applied to your db, to generate the migration script you need to revert them first.
3. Inspect the newly created migration file in the `migrations` directory and make sure `migrations/LATEST` points to the newly created migration.

## Production migrations

### Existing tables

We use [Skeefree](https://github.com/github/skeefree) to automate our migrations. To alter an existing
table just create a PR that does so and the automation will take over
from there. [Example PR from `github/launch`](https://github.com/github/launch/pull/2561/). Note that
it is acceptable to include other non-migration changes in the PR as the migration will be applied for
you _before_ the PR is deployed.

To see the status of your PR you can run the chatop: `.skeefree sup`.

### Adding tables/manual process

In this case the `vschema.json` also needs updating to mention the new
table, by adding it with the empty object, e.g.

```json
  "ts_alert_links": {},
```

### Testing indexes against production data

You can clone a production database table using the chatop:

```text
.mysql clone <TABLE> turboscan turboscan
```

After some period of time this will create a replica of the table on a clones cluster.

You can access this from a bastion shell with:

```shell
gh-dbconsole clones
```

Your clone will be in a schema that matches your handle, e.g:

```shell
USE monalisa;
```

At this point you can add indexes or columns and see how they perform with real data!

There is no need to clean the cloned table up when you are done - in fact you cannot! It will be manually removed by someone from the DBA team
after some amount of time.

### Running migrations

There's no need to manually run production migrations. Rather, when you open a migration PR, a comment will be auto-appended containing details of a label to add once the PR has been approved. All you need to do is add this label and the DB team will take it from there.
