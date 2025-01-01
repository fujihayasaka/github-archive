CREATE TABLE `ts_analysis_extracted_files_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `analysis_id` bigint unsigned NOT NULL,
  `path` text NOT NULL,
  `message` text NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_analysis_extracted_files_messages_repository_analysis_id` (`repository_id`, `analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
