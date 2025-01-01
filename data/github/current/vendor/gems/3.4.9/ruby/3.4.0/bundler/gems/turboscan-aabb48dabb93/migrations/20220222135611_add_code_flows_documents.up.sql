ALTER TABLE `ts_physical_alerts` ADD COLUMN `code_flows_document_id` bigint(20) unsigned DEFAULT NULL;
CREATE TABLE `ts_code_flows_documents` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `document` json NOT NULL,
  `hash` binary(32) GENERATED ALWAYS AS (unhex(sha2(`document`,256))) STORED,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repository_id_hash` (`repository_id`,`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
