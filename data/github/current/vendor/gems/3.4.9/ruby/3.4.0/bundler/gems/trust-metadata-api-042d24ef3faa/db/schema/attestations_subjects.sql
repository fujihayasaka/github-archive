CREATE TABLE `attestations_subjects` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `subject_digest` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject_name` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  `attestation_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_subject_and_attestation_id` (`subject_digest`,`subject_name`,`attestation_id`),
  KEY `attestations_id_attestations_subjects_idx` (`attestation_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
