DROP TABLE IF EXISTS `artifact_deployment_record_tags`;
CREATE TABLE `artifact_deployment_record_tags` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `deployment_record_id` bigint unsigned NOT NULL,
  `tag_name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `tag_value` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_artifact_deployment_record_tags_on_deployment_record_id` (`deployment_record_id`),
  KEY `index_artifact_deployment_record_tags_on_tag_name` (`tag_name`),
  KEY `index_artifact_deployment_record_tags_on_tag_value` (`tag_value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `artifact_deployment_records`;
CREATE TABLE `artifact_deployment_records` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `logical_environment` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `physical_environment` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '',
  `cluster` varchar(64) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT '',
  `deployment_name` varchar(128) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `artifact_metadata_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_logical_environment_physical_environment_clu_88376deca8` (`logical_environment`,`physical_environment`,`cluster`,`deployment_name`),
  KEY `index_artifact_deployment_records_on_artifact_metadata_id` (`artifact_metadata_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `artifact_metadata`;
CREATE TABLE `artifact_metadata` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `tenant_id` bigint unsigned NOT NULL DEFAULT '0',
  `owner_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `attestation_id` bigint unsigned DEFAULT NULL,
  `name` varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `version` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `digest` varchar(256) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `status` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL DEFAULT 'Active',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_artifact_metadata_on_repository_id_and_digest` (`repository_id`,`digest`),
  KEY `index_artifact_metadata_on_digest` (`digest`),
  KEY `index_artifact_metadata_on_owner_id` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `artifact_storage_records`;
CREATE TABLE `artifact_storage_records` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `artifact_metadata_id` bigint unsigned NOT NULL,
  `registry_url` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `registry_repository_name` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `artifact_url` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `deleted_at` datetime(6) DEFAULT NULL,
  `source_registry` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `artifact_path` varchar(512) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_artifact_storage_records_on_artifact_metadata_id` (`artifact_metadata_id`),
  KEY `index_artifact_storage_records_on_registry_url` (`registry_url`(256)),
  KEY `index_artifact_storage_records_on_source_registry` (`source_registry`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
