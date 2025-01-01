
-- name: StoreAttestation :execresult
INSERT INTO attestations(
  domain_id,
  purl,
  owner_id,
  repository_id,
  certificate,
  media_type,
  predicate_type,
  statement_type,
  statement,
  created_at,
  tenant_id,
  signer
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
);

-- name: StoreRelease :execresult
INSERT INTO releases(
  attestation_id,
  tenant_id,
  repository_id,
  tag
) VALUES (
  ?, ?, ?, ?
);

-- name: ListAttestationsByOwnerSubjectDigest :many
SELECT
  id,
  certificate,
  created_at,
  domain_id,
  media_type,
  owner_id,
  predicate_type,
  purl,
  repository_id,
  statement_preview,
  statement_type,
  statement,
  subject_digest,
  subject_name,
  tenant_id,
  signer
FROM
  (
    SELECT
      attestations.id,
      certificate,
      created_at,
      domain_id,
      media_type,
      owner_id,
      predicate_type,
      purl,
      repository_id,
      statement_preview,
      statement_type,
      statement,
      attestations_subjects.subject_digest,
      attestations_subjects.subject_name,
      tenant_id,
      signer
    FROM
      attestations
      JOIN attestations_subjects ON attestations.id = attestations_subjects.attestation_id
    WHERE
      IF(sqlc.arg (before), attestations.id > sqlc.arg (before), TRUE)
      AND IF(sqlc.arg (after), attestations.id < sqlc.arg (after), TRUE)
      AND deleted_at IS NULL
      AND domain_id = sqlc.arg (domain_id)
      AND owner_id = sqlc.arg (owner_id)
      AND IF(
        sqlc.arg(predicate_type) != "",
        REGEXP_LIKE(predicate_type, sqlc.arg(predicate_type)),
        TRUE
      )
      AND IF(
        sqlc.arg (repository_id),
        repository_id = sqlc.arg (repository_id),
        TRUE
      )
      AND attestations_subjects.subject_digest = sqlc.arg (subject_digest)
    ORDER BY
      CASE
        WHEN sqlc.arg (order_by) = 'ASC' THEN attestations.id
      END ASC,
      CASE
        WHEN sqlc.arg (order_by) = 'DESC' THEN attestations.id
      END DESC,
      id DESC
    LIMIT
      ?
  ) AS attestations
ORDER BY
  id DESC;

-- name: ListAttestationsByOwnerSubjectDigests :many
SELECT
    id,
    certificate,
    created_at,
    domain_id,
    media_type,
    owner_id,
    predicate_type,
    purl,
    repository_id,
    statement_preview,
    statement_type,
    statement,
    subject_digest,
    subject_name,
    tenant_id
FROM
    (
        SELECT
            attestations.id,
            certificate,
            created_at,
            domain_id,
            media_type,
            owner_id,
            predicate_type,
            purl,
            repository_id,
            statement_preview,
            statement_type,
            statement,
            attestations_subjects.subject_digest,
            attestations_subjects.subject_name,
            tenant_id
        FROM
            attestations
                JOIN attestations_subjects ON attestations.id = attestations_subjects.attestation_id
        WHERE
            IF(sqlc.arg (before), attestations.id > sqlc.arg (before), TRUE)
          AND IF(sqlc.arg (after), attestations.id < sqlc.arg (after), TRUE)
          AND deleted_at IS NULL
          AND domain_id = sqlc.arg (domain_id)
          AND owner_id = sqlc.arg (owner_id)
          AND IF(
                sqlc.arg(predicate_type) != "",
                REGEXP_LIKE(predicate_type, sqlc.arg(predicate_type)),
                TRUE
              )
          AND IF(
                sqlc.arg (repository_id),
                repository_id = sqlc.arg (repository_id),
                TRUE
              )
          AND attestations_subjects.subject_digest IN (sqlc.slice(subject_digests))
        ORDER BY
            CASE
                WHEN sqlc.arg (order_by) = 'ASC' THEN attestations.id
                END ASC,
            CASE
                WHEN sqlc.arg (order_by) = 'DESC' THEN attestations.id
                END DESC,
            id DESC
            LIMIT
      ?
    ) AS attestations
GROUP BY id
ORDER BY
    id DESC;

-- name: GetAttestationByRepository :one
SELECT
  attestations.id,
  certificate,
  created_at,
  domain_id,
  media_type,
  owner_id,
  predicate_type,
  purl,
  repository_id,
  statement_preview,
  statement_type,
  statement,
  tenant_id,
  attestations_subjects.subject_digest,
  attestations_subjects.subject_name
FROM attestations
JOIN attestations_subjects
  ON attestations.id = attestations_subjects.attestation_id
WHERE attestations.id = ?
  AND deleted_at IS NULL
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
  AND repository_id = sqlc.arg(repository_id);

-- name: GetAttestationSummaryByRepository :one
SELECT
  attestations.id,
  certificate,
  created_at,
  owner_id,
  predicate_type,
  repository_id,
  tenant_id,
  attestations_subjects.subject_digest,
  attestations_subjects.subject_name
FROM attestations
JOIN attestations_subjects
  ON attestations.id = attestations_subjects.attestation_id
WHERE attestations.id = ?
  AND deleted_at IS NULL
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
  AND repository_id = sqlc.arg(repository_id);

-- name: GetSubjectByAttestation :many
SELECT
  subject_digest,
  subject_name
FROM
  attestations_subjects
WHERE
  attestation_id = ?
LIMIT 1024;

-- name: ListBundleIdentifiersByAttestationId :many
SELECT
  attestations.id AS id,
  created_at,
  owner_id,
  repository_id
FROM
  attestations
WHERE deleted_at IS NULL
  AND attestations.id IN (sqlc.slice(attestation_ids))
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
ORDER BY
  attestations.id ASC
LIMIT
  ?;

-- name: ListBundleIdentifiersBySubjectDigest :many
SELECT
  attestations.id AS id,
  created_at,
  owner_id,
  repository_id,
  attestations_subjects.subject_digest
FROM
  attestations
JOIN attestations_subjects
  ON attestations.id = attestations_subjects.attestation_id
WHERE deleted_at IS NULL
  AND attestations_subjects.subject_digest IN (sqlc.slice(subject_digests))
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
GROUP BY
  attestations_subjects.subject_digest
ORDER BY
  attestations.id ASC
LIMIT
  ?;

-- name: ListAttestationSummariesByRepository :many
-- First get the subject count for each attestation
-- ahead of time so it can be joined later on in another CTE
-- Filter out deleted status and owner information and only return select columns
WITH filtered_attestations AS (
  SELECT
    attestations.id AS attestation_id,
    certificate,
    created_at,
    domain_id,
    owner_id,
    predicate_type,
    repository_id,
    tenant_id
  FROM
    attestations
  WHERE
    deleted_at IS NULL
    AND domain_id = sqlc.arg(domain_id)
    AND owner_id = sqlc.arg(owner_id)
    AND repository_id = sqlc.arg(repository_id)
  GROUP BY attestations.id
),
-- Filter out attestations further based on cursor and order by parameters
-- and join the subject count
paginated_attestations AS (
  SELECT
    fa.attestation_id AS paginated_attestation_id,
    fa.certificate,
    fa.created_at,
    fa.domain_id,
    fa.owner_id,
    fa.predicate_type,
    fa.repository_id,
    fa.tenant_id
  FROM
    filtered_attestations fa
  WHERE
    (sqlc.narg(before) IS NULL OR attestation_id > sqlc.narg(before))
    AND (sqlc.narg(after) IS NULL OR attestation_id < sqlc.narg(after))
  ORDER BY
    CASE WHEN sqlc.arg(order_by) = 'ASC' THEN attestation_id END ASC,
    CASE WHEN sqlc.arg(order_by) = 'DESC' THEN attestation_id END DESC,
    attestation_id DESC
  LIMIT
    ?
),
subject_counts AS (
  SELECT
    attestation_id AS attestations_subject_id,
    subject_name,
    COUNT(*) AS subject_count
  FROM
    attestations_subjects
  JOIN paginated_attestations pa
    ON attestation_id = pa.paginated_attestation_id
  GROUP BY
    attestation_id
),
-- Get the total row count from the filtered_attestations CTE
-- This returns the total number of matching attestations before pagination is applied
row_count AS (
  SELECT
    COUNT(attestation_id) AS total_rows
  FROM
    filtered_attestations
)
-- Finally, return the paginated attestations and the total row count
-- as a single result set
SELECT
  pa.paginated_attestation_id AS id,
  pa.certificate,
  pa.created_at,
  pa.domain_id,
  pa.owner_id,
  pa.predicate_type,
  pa.repository_id,
  pa.tenant_id,
  rc.total_rows,
  COALESCE(sc.subject_count, 0) AS subject_count,
  sc.subject_name
FROM
  paginated_attestations pa
JOIN
  subject_counts sc
  ON pa.paginated_attestation_id = sc.attestations_subject_id
CROSS JOIN
  row_count rc
ORDER BY
  id DESC;

-- name: DeleteAttestationsById :execresult
UPDATE attestations
SET deleted_at = ?
WHERE
  deleted_at IS NULL
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
  AND (sqlc.narg(repository_id) IS NULL OR repository_id = sqlc.narg(repository_id))
  AND id IN (sqlc.slice(attestation_ids));

-- name: DeleteAttestationsBySubjectDigest :execresult
UPDATE attestations
JOIN attestations_subjects ON attestations.id = attestations_subjects.attestation_id
SET deleted_at = sqlc.arg(deleted_at)
WHERE 
  deleted_at IS NULL
  AND domain_id = sqlc.arg(domain_id)
  AND owner_id = sqlc.arg(owner_id)
  AND (sqlc.narg(repository_id) IS NULL OR repository_id = sqlc.narg(repository_id))
  AND attestations_subjects.subject_digest IN (sqlc.slice(subject_digests));

-- name: GetHydroDeleteRecordInfoByID :many
SELECT
  certificate,
  owner_id,
  predicate_type,
  repository_id,
  tenant_id,
  JSON_ARRAYAGG(JSON_OBJECT("name", attestations_subjects.subject_name, "digest", attestations_subjects.subject_digest)) as subjects
FROM attestations
JOIN attestations_subjects
  ON attestations.id = attestations_subjects.attestation_id
WHERE attestations.id IN (sqlc.slice(attestation_ids))
GROUP BY
  attestations.id;

-- name: GetHydroDeleteRecordInfoByOwnerSubjectDigest :many
SELECT
  certificate,
  attestations.id,
  owner_id,
  predicate_type,
  repository_id,
  tenant_id,
  JSON_ARRAYAGG(JSON_OBJECT("name", attestations_subjects.subject_name, "digest", attestations_subjects.subject_digest)) as subjects
FROM attestations
JOIN attestations_subjects
  ON attestations.id = attestations_subjects.attestation_id
WHERE 
  attestations.owner_id = sqlc.arg(owner_id)
  AND attestations.domain_id = sqlc.arg(domain_id)
  AND attestations_subjects.subject_digest IN (sqlc.slice(subject_digests))
GROUP BY
  attestations.id;
