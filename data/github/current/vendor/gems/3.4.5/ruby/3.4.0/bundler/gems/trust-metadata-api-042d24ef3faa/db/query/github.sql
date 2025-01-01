
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
  tenant_id
) VALUES (
  ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
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

-- name: ListAttestationSummariesByRepository :many
SELECT
  *
FROM
  (
    SELECT
      attestations.id,
      certificate,
      created_at,
      domain_id,
      owner_id,
      predicate_type,
      repository_id,
      tenant_id,
      COUNT(attestations_subjects.id) AS subject_count
    FROM
      attestations
      JOIN attestations_subjects ON attestations.id = attestations_subjects.attestation_id
    WHERE
      IF(sqlc.arg(before), attestations.id > sqlc.arg(before), TRUE)
      AND IF(sqlc.arg(after), attestations.id < sqlc.arg(after), TRUE)
      AND deleted_at IS NULL
      AND domain_id = sqlc.arg(domain_id)
      AND owner_id = sqlc.arg(owner_id)
      AND repository_id = sqlc.arg(repository_id)
      AND IF(sqlc.arg(predicate_type) != "",
        REGEXP_LIKE(predicate_type, sqlc.arg(predicate_type)),
        TRUE
      )
      AND IF(sqlc.arg(partial_subject_name) != "",
        -- This subquery allows us to filter by subject name but also makes
        -- sure the returned subject_count includes all subjects associated with
        -- an attestation. Not the subject whose name matches the filter.
        attestations.id IN (
          SELECT attestation_id
          FROM attestations_subjects
          WHERE attestations_subjects.subject_name LIKE sqlc.arg(partial_subject_name)
        ),
        TRUE
      )
      AND IF(sqlc.arg(created) != "" AND sqlc.arg(created_operator) != "",
        (
          CASE
            WHEN sqlc.arg(created_operator) = '>' THEN CAST(created_at AS DATE) > sqlc.arg(created)
            WHEN sqlc.arg(created_operator) = '<' THEN CAST(created_at AS DATE) < sqlc.arg(created)
            WHEN sqlc.arg(created_operator) = '=' THEN CAST(created_at AS DATE) = sqlc.arg(created)
            ELSE TRUE
          END
        ),
        TRUE
      )
    GROUP BY attestations.id
    ORDER BY
      CASE WHEN sqlc.arg(order_by) = 'ASC' THEN attestations.id END ASC,
      CASE WHEN sqlc.arg(order_by) = 'DESC' THEN attestations.id END DESC,
      attestations.id DESC
    LIMIT
      ?
  ) AS attestations
ORDER BY
  id DESC;

-- name: DeleteAttestationsById :execresult
UPDATE attestations
SET deleted_at = ?
WHERE id IN (sqlc.slice(attestation_ids));
