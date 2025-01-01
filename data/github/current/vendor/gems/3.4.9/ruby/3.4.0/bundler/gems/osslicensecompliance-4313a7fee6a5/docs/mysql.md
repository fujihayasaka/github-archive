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

## Staging

### Getting cluster information

[Navigate to ProfessorX](https://professorx.githubapp.com/mysql/cluster/osslicensecompliance-staging)

If you just need to run queries in the database,

```shell
export OLC_MYSQL_STAGING_HOST=vtgate.vitess-staging.service.github.net
export OLC_MYSQL_STAGING_PORT=3306
```

- read-only access
  - `export OLC_MYSQL_STAGING_USER=osslicensecompliance_st_ro_0`
- read/write access:
  - `export OLC_MYSQL_STAGING_USER=osslicensecompliance_st_rw_0`
- in either case, you need to copy the associated password
  - ` export OLC_MYSQL_STAGING_PASSWORD=`

If you need to make database schema changes (through Skeema), you'll need to look on the Servers tab for a host that looks something like `db-mysql-0bdb58b.azure-eastus.github.net`.

`export OLC_MYSQL_STAGING_HOST=`

`export OLC_MYSQL_STAGING_USER=osslicensecompliance_st_super_0`

Then copy the super user password:

` export OLC_MYSQL_STAGING_PASSWORD=`

#### Port forwarding through shell

You can use ssh forwarding through the shell to access the cluster.

`ssh shell -N -L 12345:$OLC_MYSQL_STAGING_HOST:3306`

This sets up a local port (12345) that connects to 3306 on the staging host. You'll either need to background that command or open a new shell (and set the environment variables again).

```shell
export OLC_MYSQL_STAGING_HOST=localhost
export OLC_MYSQL_STAGING_PORT=12345
```

#### Connect to the cluster via prod VPN

Alternatively, you can connect via the prod VPN ([setup instructions](https://thehub.github.com/security/security-operations/production-vpn-access/)).

### Accessing mysql

```shell
mysql -u $OLC_MYSQL_STAGING_USER -h $OLC_MYSQL_STAGING_HOST -P $OLC_MYSQL_STAGING_PORT -D osslicensecompliance_staging --password=$OLC_MYSQL_STAGING_PASSWORD
```

### Database migrations (when using super user)

`skeema diff --password=$OLC_MYSQL_STAGING_PASSWORD --allow-unsafe staging`

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


Storage layer uses SQL for testing [here](internal/storage/storage_test.go)

Other packages use a null application with SQLite DB. See example [here](internal/twirp/server_test.go)


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
