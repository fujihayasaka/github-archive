CREATE TABLE `ts_analysis_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `analysis_id` bigint unsigned DEFAULT NULL,
  `delivery_id` bigint unsigned DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `key` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `args` json NOT NULL,

  PRIMARY KEY (`id`),
  KEY `idx_analysis_messages_on_repo_analysis_id` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
