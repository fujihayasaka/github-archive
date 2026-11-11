# MySQL


## Development

To start a local development database
1. Source env vars in `.env.example`
1. `docker compose up` to start mysql defined in `docker-compose.yml`

If you need to update your database schema, you can do so with the Skeema tool. (If you don't have Skeema, you can install it with homebrew: `brew install skeema`.)

See the changes that will be made:

`skeema diff --password=$OLC_MYSQL_ROOT_PASSWORD --allow-unsafe`

To apply the changes:

`skeema push --password=$OLC_MYSQL_ROOT_PASSWORD --allow-unsafe`

## Production

### Cluster & Schema

- Cluster: dependency-snapshots-api
- Schema: oss_license_compliance 

We are using a cluster that was originally provisioned for DS-API.

[ProfessorX](https://professorx.githubapp.com/mysql/cluster/dependency-snapshots-api:oss_license_compliance)


If you want to run queries in the database use the `gh-dbconsole`.
SSH to an ops shell and run:
```
gh-dbconsole dependency-snapshots-api oss_license_compliance
```

### Database migrations

We are using [Skeefree](https://github.com/github/skeefree/tree/master) for production migrations in the Dotcom
environment. This is the paved path for managing database schemas at GitHub.

If the PR contains a schema change the Skeema diff workflow will start the Skeefree flow on the Pull Request.
For documentation on migration flow read [How skeefree works](https://github.com/github/skeefree/blob/master/docs/how.md)

## Tests

We have 2 ways to test database interactions. 
- SQLite: inmemory database, the quickest and preferred way to write tests
- Test Containers: MySQL Docker based containers. Most accurate to deployed
  instance but tests are slow.


### SQLite

[SQLite](https://www.sqlite.org/)

Package `internal/storage/sqlite` provides a sql.DB that can be used for
testing and running locally.

`sqllite.New()` takes a string for the file location of the persisted DB.
Defaults to `":memory:"` if the string is empty, which is what we want for our
tests.


Storage layer uses SQL for testing [here](https://github.com/github/osslicensecompliance/blob/main/internal/storage/storage_test.go)

Other packages use a null application with SQLite DB. See example [here](https://github.com/github/osslicensecompliance/blob/main/internal/twirp/server_test.go)


### TestContainers

[Test containers](https://testcontainers.com/)

Test containers are slower than SQLite so only use where you specifically need
to test DB behaviour that cannot be tested via SQLite

The package `internal/storage/testmysql` can be used to create instances of a MySQL DB for testing.
It uses[Test containers](https://testcontainers.com/) [Go mysql](https://golang.testcontainers.org/modules/mysql/)

Creates an instance of mysql using docker.
You only need to have docker running where the tests are running and the test
containers library will take care of managing the images and containers for the
test. 
