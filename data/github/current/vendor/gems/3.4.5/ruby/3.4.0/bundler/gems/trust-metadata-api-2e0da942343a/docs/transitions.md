# Transitions

[Transitions](https://thehub.github.com/epd/engineering/products-and-services/internal/transitions/) is how GitHub manages backfilling data in a database.

## Overview

Transitions are a way to backfill data in a database. They are run via ChatOps in slack in the `#package-security-ops` channel. Each transition is a separate Go file in the `internal/transitions` directory. The ChatOps command calls the `transition` app binary (part of the TMA Docker container) via the Moda/K8s Job configuration. The current pattern is to run the transition in batches if there are a large number of records to backfill.

The flow looks like this:

- Create your transition logic
- Create a PR with your transition logic and get it approved
- ChatOps command is run in slack
- Moda/K8s Job is created
- Job runs the `transition` app binary which is part of the TMA Docker container
- The `transition` app binary loads the transition files and runs the transition that was specified by it's ID
- The transition runs and backfills the data in the database
- The ChatOps command will post update comments to slack and the PR
- Once the transition is complete, you can merge your PR

## Adding a new Transition

1. Create a new transition in the `internal/transitions` directory. You can use the `internal/transitions/transition_example.go` as a template.
1. Add the new transition to the `Entries` collection in the `internal/transitions/transitions.go` file. It should have a unique name and ID. The ID can be `YYYYMMDDHHMM` format.
1. Implement the `Run` method to perform the transition.
1. Test it locally and if possible write a `_test.go` test for it.
1. Run the transition locally to ensure it works as expected.
1. Create your pull request and get it reviewed.

## Testing a Transition Locally

Set the following environment variables:

```bash
# found in .env
export TMA_APP_ENV=
export TMA_AZURE_BLOB_ACCOUNT=devstoreaccount1
export TMA_AZURE_BLOB_CONTAINER=attestations
export TMA_MYSQL_HOST=127.0.0.1
export TMA_MYSQL_DATABASE=tma_dev
export TMA_MYSQL_USER=tma
export TMA_MYSQL_PASSWORD=<Found_in_.env>
export TMA_MYSQL_PORT=3337
```

You'll need to recompile the `bin/transition` binary every time you make a change:

```bash
make bin/transition
```

Then you can run the transition locally:

```bash
# running the command with example args
bin/transition run --id=<TRANSITION_ID> --min-id=1 --max-id=3 --batch-size=2
```

## Running Transitions

Transitions are run via ChatOps in slack in the `#package-security-ops` channel.

To run a transition, you can use the `.transition run` command. For example:

```text
.transitions run https://github.com/github/trust-metadata-api/pull/566 <ENVIRONMENT> run --id=<TRANSITION_ID> --min-id=<START_RECORD_ID> --max-id=<END_RECORD_ID> --batch-size=<BATCH_SIZE_IF_IMPLEMENTED>
```

This will run the transition pull request in the specified environment (staging|production) with the given parameters. The
transition should be run via a pull request so the ChatOps bot can update the PR with the progress.

Once the transition is complete, you can merge the PR and close it so we retain the transition if we ever need it again.

## Using a Read Only Replica Database Connection

The transition code expects a set of database environment variables
used to establish a connection to both the primary database
or read only replica database. These variables should be set in Vault
and are read from the transition Kubernetes job.

A connection to the primary database is configured on job start up
and is passed to each individual transition function.

If your transition only requires reading from the database, you
can configure your transition to use a read only connection
by calling the `database.BuildDBConn` function found in [internal/transitions/database/database.go](./../internal/transitions/database/database.go) in your transition's `Run` method.
A `DBConfig` struct with the primary and read only database configuration
is made available to each transition as a field in the transition
`Args` struct.

See the [blob storage transition](../internal/transitions/blob-storage-transition.go) for an example.
