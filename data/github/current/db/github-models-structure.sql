DROP TABLE IF EXISTS `models_attachments`;
CREATE TABLE `models_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `guid` varchar(36) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `uploader_id` bigint unsigned NOT NULL,
  `storage_blob_id` bigint unsigned DEFAULT NULL,
  `state` int NOT NULL DEFAULT '0',
  `size` int NOT NULL,
  `content_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_models_attachments_on_uploader_id_and_state` (`uploader_id`,`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_organization_access_rules`;
CREATE TABLE `models_organization_access_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `allow` tinyint(1) NOT NULL COMMENT 'whether this rule allows or blocks access',
  `models_publisher_id` bigint unsigned DEFAULT NULL COMMENT 'the publisher whose models the rule targets, if any',
  `catalog_item_key` varchar(80) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'the specific model the rule targets, if any',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_on_organization_id_allow_models_publisher_id_011ce96345` (`organization_id`,`allow`,`models_publisher_id`),
  KEY `index_models_organization_access_rules_on_models_publisher_id` (`models_publisher_id`),
  KEY `index_models_organization_access_rules_on_catalog_item_key` (`catalog_item_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_prompts`;
CREATE TABLE `models_prompts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `path` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `model` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_models_prompts_on_owner_id_and_repository_id` (`owner_id`,`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_publishers`;
CREATE TABLE `models_publishers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `logo_url` text COLLATE utf8mb4_unicode_520_ci,
  `dark_mode_icon` mediumblob,
  `light_mode_icon` mediumblob,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_publishers_on_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
