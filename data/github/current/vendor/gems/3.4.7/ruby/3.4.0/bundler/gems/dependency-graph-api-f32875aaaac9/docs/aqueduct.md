# Aqueduct

* [Overview](#overview)
* [Queues](#queues)
* [Documentation](#documentation)
* [Dashboards](#dashboards)
* [Local Development](#local-development)

## Overview

dg-api uses [Aqueduct](https://github.com/github/aqueduct) as a job queue for jobs that are **enqueued from dotcom.** These jobs include (but may not be limited to):

* **SyncVulnerabilities:** This job is enqueued for GHES/GHAE instances that have enabled GitHub Connect, when the vulnerability database is synced from dotcom to the instance.
* **ClearDependencies:** This job is enqueued from dotcom in several places, such as from Stafftools, to tell dg-api to clear package dependencies in the database for a given package.

## Queues

**Application name:** `dependency-graph-api`

**Chatop: `.aqueduct list dependency-graph-api`**

Last updated 2022-6-2.

```plain
┌──────────────────────────────────┬─────────────────────────────────┐
│App                               │Queue                            │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_actio│
│                                  │ns_package                       │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_defau│
│                                  │lt                               │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_actions                      │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_composer                     │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_go                           │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_maven                        │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_npm                          │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_nuget                        │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_pip                          │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_rubygems                     │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_manif│
│                                  │est_rust                         │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │dependency-graph_production_packa│
│                                  │ge                               │
├──────────────────────────────────┼─────────────────────────────────┤
│dependency-graph-api              │service-to-service               │
└──────────────────────────────────┴─────────────────────────────────┘
```

## Documentation

* [Aqueduct Docs on the The Hub](https://thehub.github.com/engineering/development-and-ops/aqueduct/)
* [Aqueduct ChatOps](https://thehub.github.com/engineering/development-and-ops/aqueduct/chatops)
* [Aqueduct API + CURL Examples](https://github.com/github/aqueduct/blob/master/docs/api.md)


## Dashboards

* [Aqueduct Developer Dashboard](https://app.datadoghq.com/dashboard/vmq-gt6-2h7/aqueductdeveloper?tpl_var_application=dependency-graph-api&live=true) - a dashboard created by the Aqueduct team that can be set to view only the `dependency-graph-api` application and provides a look at the queue stats.

## Local Development

### Running Locally as a Standalone Service (aqueduct-lite)

aqueduct-lite is running as a container in the standalone Codespace (see [codespaces.md](codespaces.md)).
If you'd like to run it outside of the container as a standalone application, see the instructions below.

If you are running dependency-graph-api locally and want to spin up your own local Aqueduct instance, you can use [aqueduct-lite](https://github.com/github/aqueduct-lite)

For running aqueduct-lite:

1. Install golang and redis (`brew install go redis`) and start redis (`brew services start redis`)
2. Clone `aqueduct-lite` (`git clone git@github.com:github/aqueduct-lite.git`)
3. `script/bootstrap`
4. `script/server`

Now you can run the dependency-graph-api aqueduct worker:

```bash
# From depdendency-graph-api:
AQUEDUCT_URL="http://127.0.0.1:8085/twirp" ruby ./script/aqueduct-worker
```

### Running Locally With Dotcom

Since dotcom starts an instance of aqueduct-lite in its Procfile, you don't have to do anything special.

You can start the dependency-graph-api aqueduct worker to listen to the dotcom instance of aqueduct-lite:

```bash
AQUEDUCT_URL="http://127.0.0.1:18081/twirp" ruby ./script/aqueduct-worker
```
