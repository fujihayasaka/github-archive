# CHANGELOG

## [0.18.0] - 2025-04-23

- Add `GetRepositoryIdsByAttestationId` method
- Add `GetRepositoryIdsBySubjectDigest` method

## [0.17.0] - 2025-04-18

- Add `GetBundlesById` method

## [0.16.1] - 2025-04-08

- Add `direction` field to `ListAttestationSummariesByRepository` request
- Add `total_count` field to `ListAttestationSummariesByRepository` response

## [0.16.0] - 2025-03-28

- Major refactor of gem internals
- New `sigstore-proto` dependency

## [0.15.1] - 2025-03-21

- Add required `owner_id` and optional `repository_id` to `DeleteAttestationsByID` request
- Add optional `repository_id` to `DeleteAttestationsBySubjectDigest` request

## [0.15.0] - 2025-03-12

- Add `DeleteAttestationsByID` endpoint
- Add `DeleteAttestationsBySubjectDigest` endpoint
- Add `ListAttestationsBySubjectDigests` endpoint

## [0.14.1] - 2025-02-26

- Add `created` to `ListAttestationSummariesByRepository` request
- Add `predicate_type` to `ListAttestationSummariesByRepository` request
- Add `predicate_type` to `ListAttestationSummariesByRepository` request

## [0.14.0] - 2025-02-04

- Add `subject_digests` to `ListAttestationsBySubjectDigest` request
- Add `predicate_type` to `ListAttestationsBySubjectDigest` request

## [0.12.0] - 2024-10-18

- Add `ListAttestationSummariesByRepository` endpoint
- Delete `ListAttestationsByRepository` endpoint

## [0.11.0] - 2024-05-23

- Add `GetAttestationSummaryByRepository` endpoint

## [0.10.3] - 2024-05-14

- Add `ListAttestationsByRepositorySummary` endpoint

## [0.10.2] - 2024-01-11

- Add `tenant_id` to ArtifactAttestation

## [0.10.1] - 2023-12-12

- Add `artifact_name` to `provenance_summary` in `ListAttestationsByRepository`
- Use `Faraday.use` instead of `Faraday::Request.register_middleware` when creating a client

## [0.10.0] - 2023-10-30

- Provenance Summary added to GetAttestationByRepository endpoint
- Provenance Summary added to ListAttestationsByRepository endpoint
- Added `created_at` to ListAttestationsByRepository & GetAttestationByRepository response

## [0.9.0] - 2023-10-20

- Update Create* endpoints to return ID of newly created attestation

## [0.8.0] - 2023-09-21

- Rename the gem `proto-trust-metadata-api` to align with other dotcom twirp API clients and avoid module naming collisions with models in dotcom.

## [0.7.0] - 2023-09-21

- Rearrange the client file structure
- Keep generated protobuf files in their own directory
- Introduce Sorbet for type checking

## [0.6.0] - 2023-09-14

- Added ListAttestationsByRepository endpoint

## [0.5.0] - 2023-09-07

- Initial version
