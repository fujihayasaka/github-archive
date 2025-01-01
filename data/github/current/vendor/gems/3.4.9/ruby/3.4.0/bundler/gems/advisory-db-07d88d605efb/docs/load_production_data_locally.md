# How to load the production database in local development environment

In the course of developing new features, it can be useful to test and explore production data.
To make this really convenient, using production data locally is the most ideal and safe.  
Note that there is no PII in advisory-db data, therefore it is generally OK to use it locally,
but, in the course of going about this, do be sure that no PII is pulled from production locally.
Don't apply this technique to other systems without confirming whether they store PII or not.

## Dumping production data and getting it locally

#### Log into bastion

```
ssh shell
```

#### Log into shell on advisory-db moda app

```
gh-k8s-shell -n advisory-db-production
```

If that command gives trouble, try this:
```
. vault-login
gh-kubeconfig general-2-ac4-iad
```

#### Do the `mysqldump`

```
echo $MYSQL_PASS
mysqldump -u $MYSQL_USER -p -h $MYSQL_HOST --databases $MYSQL_DB --quick --lock-tables=false --single-transaction --ignore-table $MYSQL_DB.versions > prod_dump.sql
```

NOTE: the `--ignore-table $MYSQL_DB.versions` is very important.  AdvisoryDB uses `papertrail` gem and thus all versions of objects are audit logged. Thus there is a HUGE
versions table, which is generally not needed for the kind of testing we are doing.  Therefore, skip dumping it to keep the dump file size manageable.

#### Copy the dump onto bastion

```
kubectl cp advisory-db-production/<pod name>:prod_dump.sql advisory_db_prod_dump.sql
```

Get the pod name for above command using:
```
kubectl get pods -n advisory-db-production
```

#### Copy the dump locally

From local machine:
```
scp shell:advisory_db_prod_dump.sql .
```

NOTE: File is ~450MB at time of writing, so this will take a few mins to copy down


## Loading the data into local DB

#### Clear the existing database

```
bin/rake db:reset
```

#### Load the data

:exclamation: First, check inside the database dump and be sure to set the database correctly.  I set it like so:
```

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `advisory-db_development` /*!40100 DEFAULT CHARACTER SET utf8 */;

USE `advisory-db_development`;

```

Then you are ready to load the data:
```
docker exec -i advisory-db_db_1 mysql < ../backup_advisory_db/2020-08-04-advisory-db-prod.sq
```

