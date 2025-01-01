# Development Database Notes

## MySQL Replication

Trust-Metadata-API uses MySQL replication in production. These are notes for working with MySQL primary and secondary read-only databases.

### Local MySQL Replication Setup - Script

To setup using the script, run the following commands.

Set the following variables in your `.env` file:

```shell
TMA_MYSQL_RO_PORT=3338
TMA_MYSQL_RO_ROOT_PASSWORD=<some password, can be the same as primary>
TMA_MYSQL_RO_DATABASE=tma_dev
TMA_MYSQL_RO_HOST=127.0.0.1
TMA_MYSQL_RO_PASSWORD=<tma password>
TMA_MYSQL_RO_USER=tma
```

Run the following commands:

```shell
# start the docker containers
make dev-start-with-replica

# run the script to set up the replica
script/dev-set-mysql-replica

# run migrations
make dev-migrate-up
```

When finished, clean up the local docker containers and zero out the Read-Only values in the `.env` file:

```shell
# stop the docker containers
make dev-clean-with-replica

# remove RO values from .env
```


### Local MySQL Replication Setup - Manual

If you want to set up local MySQL replication manually, you can follow these steps:

Set the following variables in your `.env` file:

```shell
TMA_MYSQL_RO_PORT=3338
TMA_MYSQL_RO_ROOT_PASSWORD=<some password, can be the same as primary>
TMA_MYSQL_RO_DATABASE=tma_dev
TMA_MYSQL_RO_HOST=127.0.0.1
TMA_MYSQL_RO_PASSWORD=<tma password>
TMA_MYSQL_RO_USER=tma
```

Start the Docker compose services with replication:

```shell
make  dev-start-with-replica
```

Connect to the primary database and get the primary status:

```shell
make dev-db-root-shell

mysql> SHOW MASTER STATUS\G
*************************** 1. row ***************************
             File: mysql-bin.000003  < # This Value
         Position: 157               < # This Value
     Binlog_Do_DB:
 Binlog_Ignore_DB:
Executed_Gtid_Set:
1 row in set (0.02 sec)
```

You will need the `File` and `Position` values to set up the replica.

Next, we need to create a mysql dump from the primary. Because we are using Docker, we initialize the database for `tma_dev` on creation. We need to provide that as a starting point for the replica. To avoid issues with `mysqldump` versions we'll run it through the command inside the MySQL Docker container:

```shell
docker exec tma-dev-db mysqldump --user=root --password={TMA_MYSQL_ROOT_PASSWORD} --all-databases > tmp/dev_dump.sql
```

Import the dump into the replica database:

```shell
docker exec -i tma-dev-db-replica mysql --user=root --password=#{TMA_MYSQL_RO_ROOT_PASSWORD} < tmp/dev_dump.sql
```

Connect to the replica database and set up the replication:

```shell
# Connect to the replica database
make dev-db-root-shell-replica

# Set the mysql replication values
# the values for Replication User and Password come from script/dev/mysql/init/01-primary.sql
# the values for MASTER_LOG_FILE and MASTER_LOG_POS come from the primary status
CHANGE MASTER TO
MASTER_HOST='mysql-primary',
MASTER_USER='replica_user',
MASTER_PASSWORD='replica_p4ssw0rd',
MASTER_LOG_FILE='mysql-bin.000003',
MASTER_LOG_POS=157;

# Start the replica
START SLAVE;
```

You can check the status of the replica with:

```shell
# on the replica mysql console:
SHOW SLAVE STATUS\G
```

Run the migrations like you normally would:

```shell
make dev-migrate-up
```

If you check the replication status you'll notice the `Read_Master_Log_Pos` has increased.

You've now setup a local MySQL instance with a replica.

when running `tma`, make sure it's correctly configured to use the
replica by looking for the following log message:

```
Timestamp=2024-11-13T07:51:47.128129Z SeverityText=INFO
InstrumentationScope=trust-metadata-api Body="Using read replica"
```

When finished, clean up the local docker containers and zero out the Read-Only values in the `.env` file:

```shell
# stop the docker containers
make dev-clean-with-replica

# remove RO values from .env
```
