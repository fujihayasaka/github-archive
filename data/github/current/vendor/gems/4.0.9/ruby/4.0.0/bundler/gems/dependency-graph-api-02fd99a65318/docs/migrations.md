## DG-API database migrations

### Running migrations on Dependency Graph DB

> [!IMPORTANT]
> Documentation can become out of date over time.  Look for a comment in the migrations PR you create.  If instructions have changed, you should find the current instructions in that comment. If the process has changed, please update this documentation.

* create the PR for the migrations
* [test in codespace](#testing-in-codespace) (_codespace is easiest, but not required_)
* get a DG team member approval
* in [#mysql-migrations-ops](https://github-grid.enterprise.slack.com/archives/C089676LR6D) slack channel, run the `.skeefree` command provided in the PR comment titled `Migration detected 🚀`

> [!WARNING]
> Many DG tables are in the TB range.  A migration can run across many days.

Additional reading: [database-infrastructure documentation on schema changes](https://github.com/github/databases/blob/main/docs/help/mysql/schema-changes.md).

### Testing in codespace

* create a codespace
* fetch and checkout the branch for the PR
* setup DG-API

```bash
./script/bootstrap
./script/setup
```

* run your migrations

```bash
bin/rails db:migrate
```

* start rails console

```bash
bin/rails console
```

* once loaded for dev environment, check changes in the database (_examples_)

```bash
ActiveRecord::Base.connection.execute("DESCRIBE dg_manifests").to_a
ActiveRecord::Base.connection.execute("SHOW COLUMNS FROM dg_manifests WHERE Field = 'id'").first
```

> [!NOTE]
> There are lots of ways to view the description of a table's columns.  In the examples, the first will show you the description of all columns.  The second limits the description to the `id` column.
