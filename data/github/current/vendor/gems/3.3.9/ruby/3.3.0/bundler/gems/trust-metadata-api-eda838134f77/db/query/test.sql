-- name: InsertAttestationSubject :execresult
INSERT INTO attestations_subjects(
  attestation_id,
  subject_digest,
  subject_name
) VALUES (
  ?, ?, ?
);