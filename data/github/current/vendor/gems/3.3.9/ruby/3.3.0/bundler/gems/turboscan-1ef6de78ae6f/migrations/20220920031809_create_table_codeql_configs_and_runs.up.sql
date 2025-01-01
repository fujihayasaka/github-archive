CREATE TABLE `ts_codeql_runs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `workflow` text DEFAULT NULL,
  `execution_id` varchar(255) DEFAULT NULL,
  `workflow_run_id` bigint(20) unsigned DEFAULT NULL,
  `ref` varchar(255) DEFAULT NULL,
  `sha` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `timeout_at` datetime(6) DEFAULT NULL,
  `status` tinyint(3) unsigned NOT NULL DEFAULT 0,
  PRIMARY KEY (`id`),
  KEY `index_codeql_runs_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_codeql_configs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `onboarding_status` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `languages` json NOT NULL,
  `workflow` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_codeql_configs_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
