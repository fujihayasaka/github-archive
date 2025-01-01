CREATE TABLE `ts_codeql_repos` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `enabled_at` datetime(6) NOT NULL,
  `soft_deleted_at` datetime(6) DEFAULT NULL,
  -- repo properties
  `supported_languages` json NOT NULL,
  `using_combined_languages` boolean NOT NULL default true,
  -- config fields
  `query_suite` tinyint unsigned NOT NULL DEFAULT '0',
  `threat_model` tinyint unsigned NOT NULL DEFAULT '0',
  `java_extraction_options` tinyint unsigned DEFAULT '0',
  `csharp_extraction_options` tinyint unsigned DEFAULT '0',
  -- enablement fields
  `enabled_by_actor_login` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  -- needed for triggering dynamic workfows
  `repository_grid` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  -- related codeql_configs
  `current_config_id` bigint DEFAULT NULL,
  `staged_config_id` bigint DEFAULT NULL,
  `failed_config_id` bigint DEFAULT NULL,
  `runner_label` varchar(256) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `cpp_extraction_options` tinyint unsigned DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_codeql_repos_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
