# 45. codebase reorganization

Date: 2023-08-04

## Status

Accepted

## Context

More can be found on [this](https://github.com/github/notifyd/discussions/1732)
discussion.

`notifyd` is currently a set of coupled services living in a monorepo.
There's currently no clear isolation between the different services and components and that's reflected in the code/packade structure:
- All the different services and utilities live in `cmd/`. This include:
  - Production services (`api`), even different services running the same binaries (`worker`, more about this later).
  - Utilities (`migrate`, `transition-job`, `staging-import`).
  - Testing services and utilities (`test-email`, `test-email-send`).
- All the components used to build all the services and utilities live in `internal`, mostly plainly (there are currently 33 packages there, 14 of those have subpackages.

## Decision

Our code organization should reflect our current service level coupling / isolation, as such layout:
- Provides a quick overview of what are the shared and isolated components, providing an easy path towards greater isolation.
- It sets clear boundaries about which services / utilities may be affected by which components.

This can be achieved by doing just some small changes in our codebase:
- `internal/` follows the same structure than `cmd`. All the binaries that use additional packages apart from main should have an entry in `internal/`
- packages that are isolated and used exclusively by some program should be internal to that program: e.g. `internal/mobile/text`
- shared packages are moved to `internal/pkg`, following the conventions in https://github.com/golang-standards/project-layout#internal

## Consequences

As a result of this transformation, our codebase should move from something like this:

```
internal
├── api
│   ├── apiservice
│   ├── chatopsserver
│   ├── chatopsservice
│   ├── devicetokensserver
│   ├── routingsettingsserver
│   └── subscriptionsserver
├── app
├── aqueduct
├── auth
├── cli
│   └── staging-import
├── compress
│   └── zlib
├── config
├── datastructures
├── deliverytracking
├── dotcom
│   ├── policy
│   └── processor
├── email
│   ├── aqueduct
│   ├── body
│   │   └── testdata
│   ├── config
│   ├── datastructures
│   ├── hydro
│   ├── layout
│   │   ├── basic
│   │   ├── header
│   │   ├── raw
│   │   └── views
│   │       └── templates
│   │           └── plain
│   └── testdata
├── errors
├── featureflags
├── featureswitches
├── http
├── hydro
│   └── testhelper
├── job
│   └── middlewares
├── layouts
├── match_engine
│   └── dto
├── metrics
├── mobile
│   ├── aqueduct
│   ├── clients
│   ├── deliveries
│   ├── devicetokens
│   │   └── testhelper
│   └── layout
│       └── basic
├── mysql
│   ├── query
│   └── testhelper
├── notify
│   └── stages
├── o11y
│   ├── exceptions
│   ├── logs
│   │   └── integration_test
│   ├── meta
│   ├── stats
│   └── tags
├── pprof
├── process
├── retries
│   └── retriables
├── routing_settings
├── schema
├── shutdown
├── subscriptions
├── text
└── transitions
    └── t2022-05-12-team-ship-notification-filters
```

into something like this:

```
internal
├── api
│   ├── apiservice
│   ├── chatopsserver
│   ├── chatopsservice
│   ├── devicetokensserver
│   ├── routingsettingsserver
│   └── subscriptionsserver
├── email
│   ├── aqueduct
│   ├── body
│   │   └── testdata
│   ├── config
│   ├── datastructures
│   ├── hydro
│   ├── layout
│   │   ├── basic
│   │   ├── header
│   │   ├── raw
│   │   └── views
│   │       └── templates
│   │           └── plain
│   └── testdata
├── migrate
├── mobile
│   ├── aqueduct
│   ├── clients
│   ├── deliveries
│   ├── devicetokens
│   │   └── testhelper
│   ├── layout
│   │   └── basic
│   └── text
├── notify
│   ├── auth
│   ├── featureflags
│   ├── featureswitches
│   └── stages
├── pkg
│   ├── aqueduct
│   ├── compress
│   │   └── zlib
│   ├── config
│   ├── datastructures
│   ├── deliverytracking
│   │   └── hydro
│   │       └── testhelper
│   ├── dotcom
│   │   ├── policy
│   │   └── processor
│   ├── errors
│   ├── http
│   ├── job
│   │   └── middlewares
│   │       └── retries
│   │           └── retriables
│   ├── layouts
│   ├── match_engine
│   │   └── dto
│   ├── metrics
│   ├── mysql
│   │   ├── query
│   │   └── testhelper
│   ├── o11y
│   │   ├── exceptions
│   │   ├── logs
│   │   │   └── integration_test
│   │   ├── meta
│   │   ├── stats
│   │   └── tags
│   ├── pprof
│   ├── process
│   ├── routing_settings
│   ├── shutdown
│   └── subscriptions
├── staging-import
└── transition-job
    └── t2022-05-12-team-ship-notification-filters
```
