# Service Details

## Service Interactions

The following diagram shows how the different Twirp
[service](https://github.com/github/trust-metadata-api/blob/main/rpc/tma/v0/service.proto)
endpoints interact with the
[`TMAService`](https://github.com/github/trust-metadata-api/blob/main/pkg/service/service.go)
functions and, ultimately, with the different
[SQL queries](https://github.com/github/trust-metadata-api/blob/main/db/query/query.sql).

The core software architecture for TMA is organized into the following layers:

- Transport Layer: Twirp & HTTP Endpoints
- Service Layer: Business Logic
- Data Layer: Database & SQL Queries

```mermaid
flowchart LR
    %% Transport Layer - GitHubAPI
    subgraph "GitHubAPI (Twirp)"
      T_CABOR[CreateAttestationByOwnerRepository]
      T_GABR[GetAttestationByRepository]
      T_GASumBR[GetAttestationSummaryByRepository]
      T_LABRS[ListAttestationsByRepositorySummary]
      T_LASBR[ListAttestationSummariesByRepository]
      T_LABSD[ListAttestationsBySubjectDigest]
    end
    %% Transport Layer - npm
    subgraph "NPM"
      subgraph "PackageInfoWriteAPI (Twirp)"
        T_CPA[CreatePackageAttestation]
      end
      subgraph "PackageInfoReadAPI (Twirp)"
        T_GPA[GetPackageAttestations]
        T_GPPS[GetPackageProvenanceSummary]
      end
    end

    %% Transport Layer -> Service Layer Connections
    %% GitHubAPI
    T_CABOR-->S_CA
    T_GABR-->S_GABR
    T_GASumBR-->S_GASumBR
    T_LABSD-->S_LABSD
    T_LABRS-->S_LABR
    T_LASBR-->S_LASBR
    %% NPM
    T_GPA-->S_GNA
    T_GPPS-->S_GPAS
    T_CPA-->S_CNA

    %% Service Layer
    subgraph TMA
      %% Service Layer - GitHub
      S_CA[CreateAttestation]
      S_GABR[GetAttestationByRepository]
      S_GASumBR[GetAttestationSummaryByRepository]
      S_LABSD[ListAttestationsBySubjectDigest]
      S_LASBR[ListAttestationSummariesByRepository]
      S_LABR[ListAttestationsByRepository]
      %% Service Layer - npm
      subgraph "tma/npm"
        S_CNA[CreateNPMAttestation]
        S_GNA[GetNPMAttestations]
        S_GPAS[GetProvenanceAttestationSummary]
      end
    end

    %% Service Layer -> Data Layer Connections
    %% TMA
    S_CA-->D_SA
    S_GABR-->D_GABR
    S_GASumBR-->D_GASumBR
    S_LABR-->D_LABR
    S_LABSD-->D_LABOSD
    S_LASBR-->D_LASBR
    %% tma/npm
    S_CNA-->D_SNA
    S_GNA-->D_GABP
    S_GPAS-->D_GABPPT

    %% Data Layer
    subgraph "SQL Query"
      %% Data Layer - GitHub
      D_SA[StoreAttestation]
      D_GABR[GetAttestationByRepository]
      D_GASumBR[GetAttestationSummaryByRepository]
      D_LABOSD[ListAttestationsByOwnerSubjectDigest]
      D_LABR[ListAttestationsByRepository]
      D_LASBR[ListAttestationSummariesByRepository]

      %% Data Layer - npm
      subgraph "SQL Query (NPM)"
        D_GABPPT[GetAttestationByPurlPredicateType]
        D_GABP[GetAttestationByPurl]
        D_SNA[StoreNPMAttestation]
      end
    end
```

## Service Consumers

### GitHubAPI

All endpoints consumed by `github/github`.

#### GetAttestationByRepository

Used for GitHub UI:

- `/attestations/{id}/download` (attestations#download_attestation)

#### GetAttestationSummaryByRepository

Used for GitHub UI:

- `/attestations/{id}` (attestations#show)

#### ListAttestationsByRepositorySummary

Used for GitHub UI:

- `/attestations` (attestations#index)

#### CreateAttestationByOwnerRepository

Used for GitHub API:

- `POST /repositories/{repository_id}/attestations`

#### ListAttestationsBySubjectDigest

Used for GitHub API:

- `GET /repos/{repo}/attestations/{subject_digest}`
- `GET /orgs/{org}/attestations/{subject_digest}`
- `GET /users/{user}/attestations/{subject_digest}`

### NPM

All endpoints consumed by `npm`.

#### PackageInfoWriteAPI/CreatePackageAttestation

Used to create attestations for npm packages

#### PackageInfoReadAPI/GetPackageAttestations

Used to get attestations for npm packages

#### PackageInfoReadAPI/GetPackageProvenanceSummary

Used to get provenance summary for an npm package
