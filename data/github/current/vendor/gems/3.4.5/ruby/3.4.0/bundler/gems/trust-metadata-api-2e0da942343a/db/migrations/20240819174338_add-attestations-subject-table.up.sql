CREATE TABLE attestations_subjects (
  id                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY,
  subject_digest    VARCHAR(256) COLLATE utf8mb4_unicode_ci NOT NULL,
  subject_name      VARCHAR(256) COLLATE utf8mb4_unicode_ci NOT NULL,
  attestation_id    BIGINT UNSIGNED NOT NULL,
  UNIQUE KEY        `index_on_subject_and_attestation_id` (`subject_digest`, `subject_name`, `attestation_id`)
);
