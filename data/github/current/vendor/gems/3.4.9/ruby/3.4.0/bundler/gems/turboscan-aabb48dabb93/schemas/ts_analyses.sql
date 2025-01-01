-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_analyses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `soft_deleted_at` datetime(6) DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `ref_bytes` varbinary(1024) NOT NULL,
  `commit_oid` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `tool_id` bigint unsigned NOT NULL,
  `tool_version_id` bigint unsigned NOT NULL,
  -- Category values are truncated to 1000 char but this field is defined with a larger capacity. See https://github.com/github/code-scanning/issues/12629
  `analysis_category` varchar(1024) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `analysis_run_id` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `environment` json NOT NULL, -- Deprecated (see https://github.com/github/code-scanning/issues/3518). Use analysis_category.
  `most_recent` tinyint(1) NOT NULL DEFAULT '0',
  `analysis_complete` tinyint(1) NOT NULL DEFAULT '1',
  `failed` tinyint(1) NOT NULL DEFAULT '0',
  `build_started_at` datetime(6) DEFAULT NULL,
  `workflow_run_id` bigint unsigned DEFAULT NULL,
  `workflow_run_attempt` bigint unsigned DEFAULT NULL,
  `upload_started_at` datetime(6) DEFAULT NULL,
  `upload_finished_at` datetime(6) DEFAULT NULL,
  `delivery_id` bigint unsigned DEFAULT NULL,
  `sarif_url` text COLLATE utf8mb4_general_ci NOT NULL,
  `sarif_id` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `analysis_key` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL, -- Deprecated (see https://github.com/github/code-scanning/issues/3518). Use analysis_category.
  `source_repository_id` bigint unsigned NOT NULL,
  `baseline_id` bigint unsigned DEFAULT NULL,
  `results_count` int unsigned DEFAULT NULL,
  `rules_count` int unsigned DEFAULT NULL,
  `process_warning` varchar(2048) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `unique_most_recent` tinyint(1) GENERATED ALWAYS AS (if(`most_recent`,1,NULL)) VIRTUAL,
  `archival_state` tinyint unsigned NOT NULL DEFAULT '0',
  `archival_failed` tinyint(1) DEFAULT '0',
  `archival_data_url` text COLLATE utf8mb4_general_ci,
  `is_outdated` tinyint(1) NOT NULL DEFAULT '0',
  `delivery_origin` tinyint unsigned NOT NULL,
  `workflow_path` varbinary(1024) DEFAULT NULL,
  `default_queries_disabled` tinyint unsigned DEFAULT NULL,
  `cleaned` tinyint(1) DEFAULT '0',
  `configuration_id` bigint unsigned DEFAULT NULL,
  `head_commit_oid` varchar(40) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_analyses_on_repo_id_deleted_recent_ref_bytes_tool_id_created` (`repository_id`,`soft_deleted_at`,`most_recent`,`ref_bytes`,`tool_id`,`created_at`),
  KEY `idx_analyses_on_repo_ids_soft_deleted_at_most_recent_tool_id` (`repository_id`,`source_repository_id`,`soft_deleted_at`,`most_recent`,`tool_id`),
  KEY `idx_analyses_on_repo_id_commit_oid` (`repository_id`,`commit_oid`),
  KEY `idx_analyses_on_repo_id_sarif_id` (`repository_id`,`sarif_id`),
  KEY `idx_analyses_on_repo_id_head_commit_oid` (`repository_id`,`head_commit_oid`),
  KEY `idx_analyses_on_repo_id_latest_for_category` (`repository_id`, `soft_deleted_at`, `is_outdated`, `most_recent`, `tool_id`, `analysis_category`(512), `id`),

  -- note: on dotcom only a subset of these indices are used
  KEY `idx_analyses_on_cleaned_updated_at` (`cleaned`,`most_recent`,`updated_at`),
  KEY `idx_analyses_on_incomplete_cleaned_updated_at` (`analysis_complete`,`most_recent`,`updated_at`),
  KEY `idx_analyses_on_archival_updated_at` (`most_recent`,`archival_state`,`archival_failed`, `failed`, `updated_at`),

  KEY `idx_analyses_on_repo_id_baseline_id` (`repository_id`,`baseline_id`),

  UNIQUE KEY `idx_analyses_on_repo_id_configuration_id_most_recent` (`repository_id`,`configuration_id`,`unique_most_recent`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
