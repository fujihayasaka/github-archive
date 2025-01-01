CREATE TABLE `ts_codeql_repos` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `soft_deleted_at` datetime(6) DEFAULT NULL,
  `supported_languages` json NOT NULL,
  `query_suite` tinyint unsigned NOT NULL DEFAULT '0',
  `threat_model` tinyint unsigned NOT NULL DEFAULT '0',
  `enabled_by_actor_login` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `repository_grid` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `current_config_id` bigint DEFAULT NULL,
  `staged_config_id` bigint DEFAULT NULL,
  `deprecated_latest_config_id` bigint DEFAULT NULL,
  `deprecated_stable_config_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_codeql_repos_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
