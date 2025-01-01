# Database Overview

We use MySQL 8 database for data storage.
Also, we use [Go Ent](https://entgo.io/) (SQL entity framework for Go) to simplify database layer.

- The database schema is located in `/schema` alongside with [skeema](https://www.skeema.io/) configuration files.
- Go Ent table definitions are stored in `/internal/store/entschema`. Generated files are stored in `/gen/ent`.

Go Ent table definitions are not synchronized with SQL schema files under `/schema` automatically.  
The usual flow:
- Prepare PR with updating DB schema, run database migration, merge PR
- Update Go Ent table definitions, regenerate ent files using `make generate`
- Implement code to interact with new tables and fields in `internal/store`

## Connect to local development database

In development environment, MySQL database is deployed to Minikube by `script/setup` script.

There are some useful scripts to interact with local database:
- `script/db-shell` - Starts the MySQL shell
- `script/db-shell --execute '<sql_query>'` - Runs the single SQL statement against MySQL database
- `script/db-setup` - Creates the database, then provision tables and seeds the data
- `script/db-setup --recreate` - Re-create existing database, then provision tables and seeds the data


You can connect to the local DB instance in a few ways:

1. Via the terminal using the following script...

    ```console
    script/db-shell
    ```

2. Using kubernetes extension and attaching a bash shell in minikube pod. After that, run the command `mysql` to run the mysql client within the minikube pod 

    <img width="551" alt="image" src="https://github.com/user-attachments/assets/9e49628b-6b6c-49c2-8016-015b246fea05">

## Connect to Lab and Production databases

There are two databases:
- Lab: https://professorx.githubapp.com/mysql/cluster/hosted-compute-ims-db-lab
- Production: https://professorx.githubapp.com/mysql/cluster/hosted-compute-ims

To connect to the database, you should:
- Connect to [production-shell](https://thehub.github.com/security/security-operations/production-shell-access/)
- Take connection data (host, port, username, password, schema) from professorx links above
- Run `mysql -h address -P port -u username -p schema_name`

> [!WARNING]  
> Use RO (Read-Only) credentials when connect to production database to make sure that you don't damage customers' data.

## Making database changes

> [!IMPORTANT]  
> Please don't mix database schema changes and other changes in the same PR. Schema migration pull-request should only include changes under `/schema` folder.

1. Make schema changes in `/schema` folder
2. [Apply changes to local database](#apply-changes-to-local-database)
3. Make a pull-request and get approvals from the team
4. [Run migration on lab database](#run-migration-on-lab-database) manually
5. [Run migration on production databases](#run-migration-on-production-databases)
6. Merge PR

As soon as schema PR is merged, you can proceed with updating Go Ent table definitions and implementing code which depends on new DB schema.

### Apply changes to local database

As soon as you make changes under `/schema` folder, you can update the local database with these changes.  
There are multiple ways to update local database:
1. The recommended way is using skeema to update local database. In this case, updating process will be pretty similar to production migration
    - `script/skeema diff`
    - `script/skeema push`
2. As an alternative, you can re-create database from scratch with new schema. It will destroy all existing data in database
    - `script/db-setup --recreate`

### Run migration on lab database

Migration of Lab database should be performed manually from local machine. Unfortunately, Codespace doesn't suite for this task because it is not possible to configure production-vpn in codespace.

Steps:
1. Ensure docker is installed on your local machine: `brew install --cask docker`
2. Ensure skeema is installed on your local machine: `brew install skeema`
2. Ensure [production-vpn](https://thehub.github.com/security/security-operations/production-vpn-access/) is configured and connected
4. Put MySQL connection password to environment variable:
    - Take password for `hosted_compute_ims_db_l_super_0` user from https://professorx.githubapp.com/mysql/cluster/hosted-compute-ims-db-lab
    - `export MYSQL_PWD="password"`
5. Pull your branch in `github/hosted-compute-ims` repository
6. Run `script/skeema diff lab` and confirm that all changes are expected
7. Run `script/skeema push lab`

### Run migration on production databases

As soon as you publish PR with schema changes, [skeema-diff.yml](../.github/workflows/skeema-diff.yml) workflow will run automatically. The workflow will analyze schema changes and post summary details to PR.  
Once PR is approved and changes are tested on Lab, you can proceed with next steps:

- Add `migration:ready:to_run` label to the PR
- `skeefree` will run and generate migration commands
- `skeefree` will then request a review from `@github/database-infrastructure`
- Wait for approval from `@github/database-infrastructure` member
- Once approved by `@github/database-infrastructure`, `skeefree` will automatically run the migration and comment as needed
- When all the migrations are complete, `skeefree` will report results to PR

Example of skeema flow on pull-request: https://github.com/github/hosted-compute-ims/pull/793

> [!TIP]
> Usually, `@github/database-infrastructure` team reviews PR within the one work day.  
> You can use chatops to prioritize your PR: `.skeefree prioritize-pr <pr_url> high`. Use this feature sparingly.

Learn more about skeefree migrations:
- https://github.com/github/skeefree/blob/master/docs/how.md#how-the-flow-looks-to-the-github-engineers
- https://github.com/github/databases/blob/main/docs/mysql/playbooks/mysql-migration.md


