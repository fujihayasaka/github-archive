-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_analyses` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `repository_nwo` varchar(140) DEFAULT NULL,
  `ref` varchar(255) NOT NULL,
  `commit_oid` varchar(40) NOT NULL,
  `analysis_name` varchar(255) NOT NULL,
  `tool` varchar(255) NOT NULL,
  `tool_version` varchar(255) NOT NULL,
  `environment` json NOT NULL,
  `most_recent` tinyint(1) DEFAULT 0,
  `analysis_complete` tinyint(1) NOT NULL DEFAULT 1,
  `started_at` datetime(6) DEFAULT NULL, -- Deprecated. Use build_started_at.
  `build_started_at` datetime(6) DEFAULT NULL,
  `workflow_run_id` int(11) DEFAULT NULL,
  `upload_started_at` datetime(6) DEFAULT NULL,
  `upload_finished_at` datetime(6) DEFAULT NULL,
  `enqueued_to_hydro_at` datetime(6) DEFAULT NULL,
  `processing_started_at` datetime(6) DEFAULT NULL,
  `processing_completed_at` datetime(6) DEFAULT NULL,
  `sarif_url` text DEFAULT NULL,
  `analysis_key` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_analyses_on_repo_id_most_recent_ref_tool` (`repository_id`, `most_recent`, `ref`, `tool`),
  KEY `idx_analyses_on_repo_id_commit_oid` (`repository_id`, `commit_oid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_enum_values` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `enum` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `value` int(11) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_enum_values_on_enum_and_name` (`enum`, `name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/* Table used to generate the sequential number column on ts_logical_alerts */
CREATE TABLE `ts_logical_alerts_seq` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `number` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_logical_alerts_seq_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
-- This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_logical_alerts` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `number` int(10) unsigned NOT NULL,
  `rule_id` bigint(20) unsigned NOT NULL,
  `resolution` int(11) NOT NULL DEFAULT 0,
  `resolver_id` int(10) unsigned DEFAULT NULL,
  `resolved_at` datetime(6) DEFAULT NULL,
  `weight` smallint(6) unsigned NOT NULL DEFAULT 0,
  `stable_alert_identifier` binary(21) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_logical_alerts_on_repository_id_and_number` (`repository_id`,`number`),
  UNIQUE KEY `index_logical_alerts_uniq_location` (`repository_id`,`stable_alert_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_physical_alerts` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `logical_alert_id` bigint(20) unsigned DEFAULT NULL,
  `rule_id` bigint(20) unsigned NOT NULL,
  `fingerprint` varchar(255) NOT NULL,
  `file_path` varchar(4096) NOT NULL,
  `start_line` int(10) unsigned DEFAULT NULL,
  `end_line` int(10) unsigned DEFAULT NULL,
  `start_column` int(10) unsigned DEFAULT NULL,
  `end_column` int(10) unsigned DEFAULT NULL,
  `stable_alert_identifier` binary(21) NOT NULL,
  `suppressed` tinyint(1) NOT NULL DEFAULT 0,
  `message` varchar(4096) NOT NULL,
  `severity_level` tinyint(3) unsigned NOT NULL,
  `analysis_id` bigint(20) unsigned NOT NULL,
  `last_seen_analysis_id` bigint(20) unsigned DEFAULT NULL,
  `file_classification` json NOT NULL,
  `has_file_classification` tinyint(1) DEFAULT 0,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_physical_alerts_uniq_location` (`repository_id`,`stable_alert_identifier`, `analysis_id`),
  KEY `idx_physical_alerts_on_repo_id_analysis_id` (`repository_id`, `analysis_id`),
  KEY `idx_physical_alerts_on_repo_id_logical_alert_id` (`repository_id`, `logical_alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_process_errors` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) NOT NULL,
  `analysis_id` bigint(20) DEFAULT NULL,
  `error_type` tinyint(3) unsigned NOT NULL,
  `sarif_uri` varchar(4096) NOT NULL,
  `json_path` varchar(4096) DEFAULT NULL,
  `message` varchar(4096) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_ref_logical_alert_states` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `ref` varchar(255) NOT NULL,
  `logical_alert_id` bigint(20) unsigned NOT NULL,
  `eliminated` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ref_logical_alert_states_on_ref_and_logical_alert_id` (`ref`, `logical_alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_related_locations` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `file_path` varchar(4096) NOT NULL,
  `start_line` int(10) unsigned DEFAULT NULL,
  `end_line` int(10) unsigned DEFAULT NULL,
  `start_column` int(10) unsigned DEFAULT NULL,
  `end_column` int(10) unsigned DEFAULT NULL,
  `message` varchar(4096) NOT NULL,
  `replacement_index` int(10) unsigned NOT NULL,
  `physical_alert_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_related_locations_on_physical_alert_id` (`physical_alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_rules` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `tool` varchar(255) NOT NULL,
  `sarif_identifier` varchar(255) NOT NULL,
  `name` varchar(255),
  `short_description` text,
  `full_description` text,
  `help_uri` varchar(1024),
  `help` mediumtext,
  `severity_level` tinyint(3) unsigned NOT NULL,
  `properties` json NOT NULL,
  `precision` varchar(255) NOT NULL,
  `precision_level` tinyint(3) unsigned NOT NULL DEFAULT 0,
  `deprecated_ids` json NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repo_tool_sarif` (`repository_id`, `tool`, `sarif_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_rule_tags` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `rule_id` bigint(20) unsigned NOT NULL,
  `tag` varchar(255) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_tag` (`tag`),
  UNIQUE KEY `index_rule_id_tag` (`rule_id`, `tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_thread_flow_locations` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `file_path` varchar(4096) NOT NULL,
  `start_line` int(10) unsigned DEFAULT NULL,
  `end_line` int(10) unsigned DEFAULT NULL,
  `start_column` int(10) unsigned DEFAULT NULL,
  `end_column` int(10) unsigned DEFAULT NULL,
  `message` varchar(4096) DEFAULT NULL,
  `code_flow_index` int(10) unsigned NOT NULL,
  `thread_flow_index` int(10) unsigned NOT NULL,
  `step_index` int(10) unsigned NOT NULL,
  `physical_alert_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_thread_flow_locations_on_physical_alert_id` (`physical_alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_timeline_events` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `logical_alert_id` bigint(20) unsigned NOT NULL,
  `event_type` tinyint(3) unsigned NOT NULL,
  `event_timestamp` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `commit_oid` varchar(40) DEFAULT NULL,
  `ref` varchar(255) DEFAULT NULL,
  `user_id` int(10) unsigned DEFAULT NULL,
  `resolution` tinyint(3) NOT NULL DEFAULT 0,
  `file_path` varchar(4096) DEFAULT NULL,
  `start_line` int(10) unsigned DEFAULT NULL,
  `tool_version` varchar(255) DEFAULT NULL,
  `analysis_id` bigint(20) DEFAULT NULL,
  `environment` json NOT NULL,
  `workflow_run_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_timeline_events_on_logical_id` (`logical_alert_id`),
  KEY `idx_timeline_events_on_analysis_id` (`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
