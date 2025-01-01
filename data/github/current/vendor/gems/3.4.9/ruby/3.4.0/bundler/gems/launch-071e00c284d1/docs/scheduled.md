# Scheduled Workflows

We support scheduled workflow execution, allowing users to run a workflow on a given [schedule](https://docs.github.com/en/actions/using-workflows/events-that-trigger-workflows#schedule). The schedule on which these workflows run is specified via cron syntax. For instance, the following YAML specifies a workflow which is scheduled to run every day at 09:05 UTC.

```YAML
on:
  schedule:
    - cron: '5 9 * * *'
```

Scheduled workflow functionality is implemented in the `scheduled` service, which is currently hosted by the deployer service.

## Overview

### Defining Schedules

Users author schedules in their workflow files. We keep that in sync with the `workflow_schedules` table:

1. Launch worker calls `scheduled` whenever a webhook event that affects schedules is received (`push` or `repository`).
1. `scheduled` synchronises the schedules defined by the user in their workflow files with the `workflow_schedules` table.

### Storing Schedules
Schedules are stored in the Launch [`workflow_schedules`](https://github.com/github/launch/blob/master/schemas/deployer/workflow_schedules.sql) table along with information about the repository and timestamp for the schedule’s next run. Launch workers (goroutines) periodically query the schedules table to find any schedules that are ready to run (indicated by `next_run_at <= UTC_TIMESTAMP`).

### Schedule Locking
Schedule locking is the mechanism we use to ensure schedules are only queued once by a single worker.
When there are multiple schedules to queue, we want to prioritize the schedules that have been delayed the most.
As part of that prioritization, we also use a tier system to prioritize schedules from paying/trusted customers over others (this tier system later became [Trust Tiers](https://thehub.github.com/support/process/trust/)).
For example, a tier 3 schedule that's delayed 12 minutes has the same priority as a tier 1 schedule that’s delayed 1 minute.

To ensure schedules are idempotent, we use a pessimistic locking scheme.
When a worker locks a row, it sets a `locked_by` column to indicate the worker and a `locked_at` timestamp to track when the row was locked.

To limit the total number of schedules we run, each worker will only schedule a certain number of schedules at a time, even if there are other schedules to run. The number of schedules is determined by the value of the [`SCHEDULE_TASKS_PER_TICK`](https://github.com/search?q=repo%3Agithub%2Flaunch%20SCHEDULE_TASKS_PER_TICK%20&type=code) configuration variable in the launch environment in question. For production, this value is currently **152**, per configuration [here](https://github.com/github/launch/blob/247f19cd12da26acad98d2e4ffb24daeb1236bfb/config/kubernetes/production/deployments/launch-deployer.yaml#L272-L273). If this configuration variable is missing in the environment for some reason, it will currently [default](https://github.com/github/launch/blob/247f19cd12da26acad98d2e4ffb24daeb1236bfb/cmd/launch-worker/config.go#L141) to a value of **10**.

So at a high level, a worker will, assuming `SCHEDULE_TASKS_PER_TICK` is present in the environment variables:

1. `UPDATE` up to `SCHEDULE_TASKS_PER_TICK` rows that aren’t locked (`locked_by IS NULL`) and are ready to be scheduled (`next_run_at <= UTC_TIMESTAMP`) for a given tier
2. `SELECT` the rows that were just locked (`locked_by = 'launch-worker-20'`)

The worker will repeat that for all three tiers. When there’s a backlog of schedules to run, the worker will have more than `SCHEDULE_TASKS_PER_TICK` schedules (up to `SCHEDULE_TASKS_PER_TICK` * 3).
The worker will sort the schedules based on their ages, which are [weighted by tier](https://github.com/github/launch/blob/3491ce11b778da994db9eecbb6ee2a1a6f3f980c/db/stores/schedules/schedule_locking.go#L71-L82), and the top `SCHEDULE_TASKS_PER_TICK` will be queued sequentially and the remaining will be "unlocked" (`SET locked_by = NULL`). Weighting schedules' ages by tier helps ensure that we avoid fetching unnecessary rows.

After a scheduled row is queued, the worker calculates when it's scheduled to run next and updates the row with the new `next_run_at` and removes the lock.

If there are errors processing a scheduled run, we could end up in a state where a worker will never queue a schedule that it locks. To account for this, another set of workers periodically unlock "stale" rows that have been locked for over three minutes.

## Running schedules

The deployer service runs jobs from the `scheduled` service periodically. The jobs pull rows from the `workflow_schedules` service when they are due to run, and queue a build. See `schedule/worker.go`.

Only schedules contained in workflow files on the default branch will be run. We observe changes to the default branch
on receipt of the `repository` webhook (the `edited` action).

## Diagram

Overview of the services and entities involved.

Source: [docs/diagrams/schedules.monopic](./diagrams/schedules.monopic)

```
┌──────────────────────────────────────────────────────────┐                                            ┌────────────────────────────────────────────────┐
│                         Deployer                         │                                            │                     dotcom                     │
│                                                          │                                            │                                                │
│    ┌───────────────────┐        ┌───────────────────┐    │  ┌───────────────────┐                     │                                                │
│    │                   │        │                   │    │  │                   │                     │ ┌───────────────────┐    ┌───────────────────┐ │
│    │                   │        │                   │    │  │                   │                     │ │                   │    │                   │ │
│    │ scheduled worker  │        │ scheduled service │◀───┼──│   launch-worker   │◀────────────────────│ │                   │    │                   │ │
│    │                   │        │                   │    │  │                   │  events affecting   │ │  Default branch   │┼───┤    Repository     │ │
│    │    .─────────.    │        │                   │    │  │                   │     schedules       │ │                   │    │                   │ │
│    └───(   Polls   )───┘        └───────────────────┘    │  └───────────────────┘ (push, repository)  │ │                   │    │                   │ │
│         `────┬────'                       │              │                                            │ └───────────────────┘    └───────────────────┘ │
└──────────────┼────────────────────────────┼──────────────┘                                            │                                    │           │
┌──────────────┼────────────────────────────┼──────────────┐                                            │                                   ╱│╲          │
│              │           MySQL            │              │                                            │                          ┌───────────────────┐ │
│              │                            │              │                                            │                          │                   │ │
│              │                            │              │                                            │                          │                   │ │
│              │                            │              │                                            │                          │   Workflow file   │ │
│              │                            │              │                                            │                          │                   │ │
│              ▼                            ▼              │                                            │                          │                   │ │
│ ┌─────────────────────────────────────────────────────┐  │                                            │                          └───────────────────┘ │
│ │                                                     │  │                                            │                                    │           │
│ │                                                     │  │                                            │                                   ╱│╲          │
│ │               workflow_schedules row                │┼─┼─────────────────────────────────┐          │                          ┌───────────────────┐ │
│ │                                                     │  │                                 │          │                          │                   │ │
│ │                                                     │  │                                 │          │                          │                   │ │
│ └─────────────────────────────────────────────────────┘  │                                 └──────────┼─────────────────────────┼│Scheduled workflow │ │
│                                                          │                                            │                          │                   │ │
│                                                          │                                            │                          │                   │ │
│                                                          │                                            │                          └───────────────────┘ │
└──────────────────────────────────────────────────────────┘                                            └────────────────────────────────────────────────┘
```

## Monitoring

There is a [DataDog dashboard](https://app.datadoghq.com/dashboard/ptq-7g7-3um) for scheduled builds.

## Schedule Tooling

### Synchronising schedules
To synchronize schedules for a given repository, you can visit the Stafftools page associated with that repo. From there, navigate as follows: `Actions` > `Scheduled workflows`. For example, launch's scheduled workflows are defined at: https://admin.github.com/stafftools/repositories/github/launch/actions/workflow_schedules. If there are any scheduled workflows, you'll see them listed in this UI, and at the top right, you'll see an option called "Resync schedules". You can click this to resychronize the listed schedules with the `workflow_schedules` table.

### Deleting Schedules
Use `.help launch schedules` to see a more concrete example of how to use the chatop associated with this functionality.

To delete the schedules for a repo, you can run:

```
.launch schedules delete <env> <repo_global_id>
```

## Notifications for Scheduled Workflow Runs

A user will be automatically subscribed to notifications for scheduled workflow runs based on the creation of, or modifications to, the scheduled workflow. The details of how a user is subscribed are discussed more in-depth in the [official](https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/notifications-for-workflow-runs) GitHub Docs.
