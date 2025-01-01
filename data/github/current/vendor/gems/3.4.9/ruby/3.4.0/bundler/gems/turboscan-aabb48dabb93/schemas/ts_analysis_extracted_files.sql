CREATE TABLE `ts_analysis_extracted_files` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `analysis_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `files_extracted` json NOT NULL,
  `files_not_extracted` json NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_analysis_extracted_files_analysis_id` (`analysis_id`),
  KEY `idx_analysis_extracted_files_repository_id_analysis_id` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
