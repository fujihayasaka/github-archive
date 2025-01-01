CREATE TABLE `ts_analysis_messages` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `analysis_id` bigint(20) unsigned NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `key` varchar(255) NOT NULL,
  `args` json NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_analysis_messages_on_repo_analysis_id` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
