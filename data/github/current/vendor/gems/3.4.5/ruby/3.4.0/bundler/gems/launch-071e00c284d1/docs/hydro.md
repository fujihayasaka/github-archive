# Actions Hydro

GitHub uses [github/hydro](https://github.com/github/hydro) as a collector for business intelligence/analytics events.
Several Actions services emit events to Hydro when interesting events occur.

## Defining Events

Hydro events are defined by a protobuf schema, in the [github/hydro-schemas](https://github.com/github/hydro-schemas/tree/main/proto/hydro/schemas/github/actions/v0) repository. Docs in that repo describe the change process.

When a new hydro event is merged into `github/hydro-schemas`, you can run `script/sync-hydro-proto` to pull in the latest schemas. These changes will be saved under `/hydro/schemas`. Because we only use a small number of the schemas inside the `/hydro/schemas/github/v1/*` package, we don't pull in all of the generated files. You will have a _lot_ of files added in this folder, but only commit changes to existing ones or anything new you now require, discard the other additions.

## Querying Events

Hydro events [propagate](https://github.com/github/data-engineering/blob/master/docs/projects/hydro/ArchitectureReview.md#data-flow) through GitHub's data pipeline, and are eventually queryable by Presto. Use this to verify fields are being filled as you expect.

Presto can be accessed through the [analytics-console](https://github.com/github/analytics-console) host, inside GitHub's network.

```
$ gh-presto console
GitHub Data Warehouse Privacy Guidelines: https://github.com/github/data-engineering/blob/master/docs/DataWarehousePrivacy.md

presto> use hive_hydro.hydro;
USE
presto:hydro> select count(id) from launch_v0_workflow_change;
 _col0
-------
 10881
(1 row)

Query 20181030_133553_10037_392su, FINISHED, 16 nodes
Splits: 479 total, 479 done (100.00%)
0:02 [10.9K rows, 1.92MB] [4.98K rows/s, 902KB/s]

presto:hydro>
```

## Publishing Mock Events

`github/launch` ships with [`launch-hydro-consumer`](/services/hydrosvc/service.go), which is responsible for consuming certain events from Hydro and acting on them for various tasks. We start up this consumer when we run `script/server`, but we do not read events from `github/github` in an end-to-end fashion. If you want to publish mock Hydro events to debug the consumer, you can simply run `hydro-debug` to continuously publish mock events. When you need to debug a new event, add it to the `produce` function [`cmd/hydro-debug/main.go`](/cmd/hydro-debug/main.go) with mock values.

## Verify in GHES

In order to listen to the events in GHES, we need to make sure if those are listed here https://github.com/github/hydro-schemas/blob/master/topic-configuration/production/enterprise/kafka-topics.yaml
