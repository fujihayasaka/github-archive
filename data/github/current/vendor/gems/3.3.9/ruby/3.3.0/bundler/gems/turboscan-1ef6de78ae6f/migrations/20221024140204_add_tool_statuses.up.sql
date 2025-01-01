CREATE TABLE `ts_tool_statuses` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `analysis_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `files_extracted` json NOT NULL,
  `files_not_extracted` json NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_tool_status_analysis_id` (`analysis_id`),
  KEY `idx_tool_status_repo_id` (`repository_id`, `analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
