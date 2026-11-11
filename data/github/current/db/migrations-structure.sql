DROP TABLE IF EXISTS `elm_exporter_authentications`;
CREATE TABLE `elm_exporter_authentications` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `migration_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `authentication_type` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `system_pat_name` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  KEY `idx_elm_exporter_authentications_migration_id` (`migration_id`),
  KEY `idx_elm_exporter_authentications_type` (`authentication_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `elm_exporter_messages`;
CREATE TABLE `elm_exporter_messages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `migration_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `message_type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `message` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  KEY `idx_elm_exporter_messages_migration_id` (`migration_id`),
  KEY `idx_elm_exporter_messages_type` (`message_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `elm_exporter_migrations`;
CREATE TABLE `elm_exporter_migrations` (
  `id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `status` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `source_organization_login` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `source_repository_name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_organization_login` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_repository_name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_visibility` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'internal',
  `target_api_endpoint` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_migration_id` bigint unsigned DEFAULT NULL,
  `source_migration_id` bigint unsigned DEFAULT NULL,
  `backfill_completed_at` datetime(6) DEFAULT NULL,
  `cutover_started_at` datetime(6) DEFAULT NULL,
  `repository_locked_at` datetime(6) DEFAULT NULL,
  `workers_paused_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `started_at` datetime(6) DEFAULT NULL,
  `completed_at` datetime(6) DEFAULT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_elm_exporter_migrations_status` (`status`),
  KEY `idx_elm_exporter_migrations_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `elm_exporter_repositories`;
CREATE TABLE `elm_exporter_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `migration_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `source_git_url` varchar(366) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_git_url` varchar(366) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `status` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_elm_exporter_repositories_urls` (`migration_id`,`source_git_url`,`target_git_url`),
  KEY `idx_elm_exporter_repositories_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `elm_exporter_work_items`;
CREATE TABLE `elm_exporter_work_items` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `migration_id` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `status` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `component` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `process_id` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `lease_expires_at` datetime(6) DEFAULT NULL,
  `work_item_type` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `work_item_data` json NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_elm_exporter_work_items_claimability` (`component`,`status`,`lease_expires_at`),
  KEY `idx_elm_exporter_work_items_migration_id_component_status` (`migration_id`,`component`,`status`),
  KEY `idx_elm_exporter_work_items_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `migratable_resource_reports`;
CREATE TABLE `migratable_resource_reports` (
  `id` int NOT NULL AUTO_INCREMENT,
  `migration_id` int NOT NULL,
  `model_type` varchar(50) NOT NULL,
  `total_count` int NOT NULL,
  `success_count` int NOT NULL,
  `failure_count` int NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_migratable_resource_reports_on_migration_id` (`migration_id`),
  KEY `index_migratable_resource_reports_on_model_type` (`model_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `migratable_resources_v2`;
CREATE TABLE `migratable_resources_v2` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `guid` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `model_id` bigint unsigned DEFAULT NULL,
  `source_url` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `target_url` text COLLATE utf8mb4_unicode_520_ci,
  `state` int DEFAULT '0',
  `migration_id` bigint unsigned DEFAULT NULL,
  `model_type` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `warning` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_migratable_resources_v2_on_guid_and_source_url` (`guid`,`source_url`(511)),
  KEY `index_migratable_resources_v2_on_guid_and_state_and_model_type` (`guid`,`state`,`model_type`),
  KEY `index_migratable_resources_v2_on_guid_and_model_type` (`guid`,`model_type`),
  KEY `index_migratable_resources_v2_on_guid_and_warning` (`guid`,`warning`(1))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `migration_export_batches`;
CREATE TABLE `migration_export_batches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `migration_id` bigint unsigned NOT NULL,
  `model_type` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `type` int NOT NULL DEFAULT '0',
  `state` int NOT NULL DEFAULT '0',
  `model_ids` json NOT NULL,
  `success_count` int NOT NULL DEFAULT '0',
  `failed_count` int NOT NULL DEFAULT '0',
  `queued_at` datetime(6) DEFAULT NULL,
  `started_at` datetime(6) DEFAULT NULL,
  `completed_at` datetime(6) DEFAULT NULL,
  `migration_file_id` bigint unsigned DEFAULT NULL,
  `critical_error` json DEFAULT NULL,
  `processing_errors` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_migration_export_batches_on_migration_id_state_batch_type` (`migration_id`,`state`,`type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `migration_files`;
CREATE TABLE `migration_files` (
  `id` int NOT NULL AUTO_INCREMENT,
  `migration_id` int NOT NULL,
  `content_type` varchar(255) NOT NULL,
  `size` bigint NOT NULL,
  `guid` varchar(36) NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  `name` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `uploader_id` int DEFAULT NULL,
  `storage_blob_id` int DEFAULT NULL,
  `oid` varchar(64) DEFAULT NULL,
  `storage_provider` varchar(30) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_migration_files_on_migration_id` (`migration_id`),
  KEY `index_migration_files_on_uploader_id` (`uploader_id`),
  KEY `index_migration_files_on_storage_blob_id` (`storage_blob_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `migration_repositories`;
CREATE TABLE `migration_repositories` (
  `id` int NOT NULL AUTO_INCREMENT,
  `migration_id` int DEFAULT NULL,
  `repository_id` int DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_migration_repositories_on_migration_id` (`migration_id`),
  KEY `index_migration_repositories_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `migration_timings`;
CREATE TABLE `migration_timings` (
  `id` int NOT NULL AUTO_INCREMENT,
  `migration_id` int NOT NULL,
  `action` int NOT NULL,
  `time_elapsed` int NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_migration_timings_on_migration_id` (`migration_id`),
  KEY `index_migration_timings_on_action` (`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `migrations`;
CREATE TABLE `migrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `guid` varchar(255) NOT NULL,
  `state` int NOT NULL,
  `lock_repositories` tinyint(1) NOT NULL DEFAULT '1',
  `creator_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `exclude_attachments` tinyint(1) DEFAULT '0',
  `migratable_resources_count` int DEFAULT NULL,
  `archive_size` bigint DEFAULT NULL,
  `source_product` varchar(50) DEFAULT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `exclude_releases` tinyint(1) NOT NULL DEFAULT '0',
  `exclude_owner_projects` tinyint(1) NOT NULL DEFAULT '0',
  `exclude_git_data` tinyint(1) NOT NULL DEFAULT '0',
  `exclude_metadata` tinyint(1) NOT NULL DEFAULT '0',
  `org_metadata_only` tinyint(1) NOT NULL DEFAULT '0',
  `import_migration_source` varchar(30) DEFAULT NULL,
  `is_gsm_migration` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_migrations_on_guid` (`guid`),
  KEY `index_migrations_on_owner_id_and_created_at` (`owner_id`,`created_at`),
  KEY `index_migrations_on_owner_id_and_guid` (`owner_id`,`guid`),
  KEY `index_migrations_on_migratable_resources_count` (`migratable_resources_count`),
  KEY `index_migrations_on_archive_size` (`archive_size`),
  KEY `index_migrations_on_business_id` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `migrations_key_values`;
CREATE TABLE `migrations_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_migrations_key_values_on_key` (`key`),
  KEY `index_migrations_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `octoshift_migration_archives`;
CREATE TABLE `octoshift_migration_archives` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned DEFAULT NULL,
  `content_type` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `size` bigint NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `uploader_id` bigint unsigned DEFAULT NULL,
  `storage_blob_id` bigint unsigned DEFAULT NULL,
  `oid` varchar(64) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `storage_provider` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `guid` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_octoshift_migration_archives_on_guid` (`guid`),
  KEY `index_octoshift_migration_archives_on_organization_id` (`organization_id`),
  KEY `index_octoshift_migration_archives_on_uploader_id` (`uploader_id`),
  KEY `index_octoshift_migration_archives_on_storage_blob_id` (`storage_blob_id`),
  KEY `index_octoshift_migration_archives_on_guid_and_organization_id` (`guid`,`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
