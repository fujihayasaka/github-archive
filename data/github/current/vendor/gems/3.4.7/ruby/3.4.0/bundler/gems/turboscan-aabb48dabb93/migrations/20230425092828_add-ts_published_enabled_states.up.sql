CREATE TABLE `ts_published_enabled_states` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `enabled` tinyint(1) DEFAULT NULL,
  `reason` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_published_enabled_state_on_repo_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
