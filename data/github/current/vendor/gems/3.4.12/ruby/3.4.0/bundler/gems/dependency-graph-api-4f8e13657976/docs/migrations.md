### Running migrations on Dependency Graph DB
As of March 2019, we now run our database on GitHub's MySQL infrastructure, which means that we aren't able to run migrations ourselves.

If you need to run a migration please refer to the [database-infrastructure documentation on schema changes](https://github.com/github/database-infrastructure/blob/master/docs/help/mysql/schema-changes.md) and then [open a schema migration issue](https://github.com/github/database-infrastructure/issues/new?template=request_schema_migration.md).