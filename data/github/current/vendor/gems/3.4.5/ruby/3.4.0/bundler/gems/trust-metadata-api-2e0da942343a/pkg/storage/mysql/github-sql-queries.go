package mysql

var listAttestationSummariesWithFilters = `
-- Filter out deleted rows and return based on matching identifiers, predicate type, and created at date
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
  LEFT JOIN attestations_subjects
    ON attestations.id = attestations_subjects.attestation_id
  WHERE
    deleted_at IS NULL
    AND domain_id = ?
    AND owner_id = ?
    AND repository_id = ?
    AND IF(
      ? != "",
      attestations_subjects.subject_name LIKE ?,
      TRUE
    )
    AND (? IS NULL OR REGEXP_LIKE(predicate_type, ?))
		AND ((? IS NULL OR ? IS NULL) OR
			(
				CASE
					WHEN ? = '>' THEN CAST(created_at AS DATE) > ?
					WHEN ? = '<' THEN CAST(created_at AS DATE) < ?
					WHEN ? = '=' THEN CAST(created_at AS DATE) = ?
					ELSE TRUE
				END
			)
		)
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
    IF(?, attestation_id > ?, TRUE)
    AND IF(?, attestation_id < ?, TRUE)
  ORDER BY
    CASE WHEN ? = 'ASC' THEN attestation_id END ASC,
    CASE WHEN ? = 'DESC' THEN attestation_id END DESC,
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
`
