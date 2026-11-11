# Hydro

This document provides information about Hydro configuration and usage.

## Overview

The usage for Hydro is to consume `github.dependencygraph.v1.SnapshotProcessed` messages. They are emitted when Dependency Snapshots are received in monolith [here](https://github.com/github/github/blob/master/app/api/repository_dependency_graph.rb#L59-L68) to track snapshot processing as part of license checking.

The main consumer code is located at: [`cmd/snapshot-processed/main.go`](https://github.com/github/osslicensecompliance/blob/main/cmd/snapshot-processed/main.go)

## Deployment

The Hydro consumer is deployed via the snapshot-processed-consumer deployment:

- **Production Deployment**: [`config/kubernetes/production/deployments/osslicensecompliance-snapshot-processed-consumer.yaml`](https://github.com/github/osslicensecompliance/blob/main/config/kubernetes/production/deployments/osslicensecompliance-snapshot-processed-consumer.yaml)

## Configuration

### Kafka Client ID (Consumer Group)

The Kafka client ID is configured as:
```
KAFKA_CLIENT_ID: osslicensecompliance-production
```

This is passed as the consumer group.

## Environment-Specific Deployment

- ✅ **Production**: Active and deployed


## Using Hydro Schema protos

To use proto schemas defined in https://github.com/github/hydro-schemas they
must be generated into Go code.
Run script
```sh
script/update-hydro-schemas
```

That will generate the code into `hydroproto/hydro/schemas/`.
This is separate from the protos in `/proto` which are in the published Gem the
monolith uses for the API.

