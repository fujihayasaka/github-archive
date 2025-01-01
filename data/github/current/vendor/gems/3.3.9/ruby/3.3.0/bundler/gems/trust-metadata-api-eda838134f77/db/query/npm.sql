-- name: StoreNPMAttestation :execresult
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

-- name: GetAttestationsByPurl :many
SELECT
  domain_id,
  attestations.id,
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
  statement_preview,
  attestations_subjects.subject_digest,
  attestations_subjects.subject_name
  FROM attestations
  JOIN attestations_subjects
    ON attestations.id = attestations_subjects.attestation_id
  WHERE purl = ?
  AND domain_id = ?;

-- name: GetAttestationByPurlPredicateType :one
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
  tenant_id
FROM
  attestations
WHERE
  purl = ?
  AND domain_id = ?
  AND predicate_type IN (sqlc.slice ('predicate_types'))
ORDER BY
  predicate_type DESC
LIMIT
  1;
