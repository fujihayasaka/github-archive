CREATE TABLE `ts_analysis_tool_versions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `analysis_id` bigint(20) unsigned NOT NULL,
  `tool_version_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_repo_analysis_toolversion` (`repository_id`,`analysis_id`,`tool_version_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
