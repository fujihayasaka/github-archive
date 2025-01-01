# API Dataflows

This document illustrates the various Snapshots API endpoints in their greater
context at GitHub, including the involvement of other services like dotcom and
dg-api.

# Snapshot operations

We have two operations that work directly on snapshots:
`CreateDependencySnapshot` and `GetDependencySnapshot`.
These are declared in the [Twirp protocol here](https://github.com/github/dependency-snapshots-api/blob/73612c99b4a644fa3a10c0d78fd568efb2b0b094/proto/snapshots.proto).

## CreateDependencySnapshot

Snapshots are created via a POST request to the
`https://api.github.com/repos/<NWO>/dependency-graph/snapshots'` endpoint. We do
minimal processing on snapshots during creation—essentially we just store the
JSON blob and create rows for the build type (if necessary) and build.

Although dg-api is involved in the request, it acts as a proxy and does no
significant work of its own here.

```mermaid
sequenceDiagram
    actor user as User
    participant dotcom
    participant dg as dg-api
    participant snaps as Snapshots Service
    participant db as Snapshots DB
    user->>dotcom: POST snapshots
    Note over dotcom: check authn/authz
    Note over dotcom: validate snapshot JSON
    dotcom->>dg: CreateDependencySnapshot request
    Note over dg: message forwarded
    dg->>snaps: CreateDependencySnapshot request
    snaps->>db: store snapshot
    db-->>snaps: snapshot ID, creation time
    snaps-->>dg: snapshot ID, creation time
    Note over dg: response forwarded
    dg-->>dotcom: snapshot ID, creation time
    dotcom-->>user: snapshot ID, creation time
    Note over dotcom: response forwarded
```

## GetDepedencySnapshot

This is _extremely_ similar to creating a snapshot in terms of data flow, but
the request and response formats are different.

```mermaid
sequenceDiagram
    actor user as User
    participant dotcom
    participant dg as dg-api
    participant snaps as Snapshots Service
    participant db as Snapshots DB
    user->>dotcom: GET snapshots/{ID}
    Note over dotcom: check authn/authz for repository
    dotcom->>dg: GetDependencySnapshot request
    Note over dg: message forwarded
    dg->>snaps: GetDependencySnapshot request
    snaps->>db: select snapshot
    db-->>snaps: raw snapshot data
    snaps-->>dg: reassembled snapshot
    Note over dg: response forwarded
    dg-->>dotcom: reassembled snapshot
    dotcom-->>user: reassembled snapshot
    Note over dotcom: response forwarded
```

# Dependencies operations

We currently support two operations that work directly on dependencies (rather than snapshots): `GetDependenciesForRepository` and `HasManifests`. They are defined in the a [Twirp protocol in the dg-api repository](https://github.com/github/dependency-graph-api/blob/4b3b8bf31027d88c435a5358674b8e69ecdd92e2/proto/twirp/v1/dependency_graph_api.proto#L47-L52).

## Retrieving dependencies for a repository (with vulnerabilities)

The dotcom service requests vulnerabilities for a repository from the `RepositoryVulnerabilityAlerter` job.
Note that the snapshots service has no notion of vulnerabilities—those are added to the response by dg-api.

```mermaid
sequenceDiagram
    participant dotcom
    Note over dotcom: RepositoryVulnerabilityAlerter Job
    participant dg as dg-api
    participant snaps as Snapshots Service
    participant db as Snapshots DB
    dotcom->>dg: GetDependenciesForRepository request
    Note over dg: message forwarded (based on feature flag)
    dg->>snaps: GetDependenciesForRepository request
    snaps->>db: select canonical snapshots for repo
    db-->>snaps: raw snapshot data
    Note over snaps: snapshots combined
    snaps-->>dg: dependencies
    Note over dg: vulnerabilities added
    dg-->>dotcom: dependencies with vulnerabilities
    Note over dotcom: alerts generated
```

## Checking whether a repository has manifests

This endpoint exists, but it is currently not used as part of any process. It returns `true` if the repository has dependency data and `false` if it does not.

# Worker processes
