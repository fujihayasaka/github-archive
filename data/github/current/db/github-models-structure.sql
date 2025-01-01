DROP TABLE IF EXISTS `custom_keys`;
CREATE TABLE `custom_keys` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'User-given name',
  `kredz_key` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Identifier for where the key is stored in kredz',
  `provider` int NOT NULL DEFAULT '0',
  `organization_id` bigint unsigned NOT NULL,
  `deployment_url` text COLLATE utf8mb4_unicode_520_ci COMMENT 'Azure deployment URL if applicable',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_custom_keys_on_organization_id_and_kredz_key` (`organization_id`,`kredz_key`),
  UNIQUE KEY `index_custom_keys_on_organization_id_and_name` (`organization_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `custom_models`;
CREATE TABLE `custom_models` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'User-provided name',
  `slug` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Identifier for this model from the provider',
  `copilot_chat_enabled` tinyint(1) NOT NULL DEFAULT '1',
  `custom_key_id` bigint unsigned NOT NULL COMMENT 'Reference to custom_keys record',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_custom_models_on_custom_key_id_and_name` (`custom_key_id`,`name`),
  UNIQUE KEY `index_custom_models_on_custom_key_id_and_slug` (`custom_key_id`,`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models`;
CREATE TABLE `models` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` json NOT NULL,
  `visibility` int NOT NULL DEFAULT '0',
  `has_free_playground` tinyint(1) NOT NULL DEFAULT '0',
  `name` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `original_name` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `friendly_name` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `source` int DEFAULT '0',
  `task` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `license` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_unicode_520_ci,
  `summary` text COLLATE utf8mb4_unicode_520_ci,
  `version` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_unicode_520_ci,
  `tags` text COLLATE utf8mb4_unicode_520_ci,
  `rate_limit_tier` varchar(60) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `supported_languages` text COLLATE utf8mb4_unicode_520_ci,
  `max_output_tokens` int DEFAULT NULL,
  `max_input_tokens` int DEFAULT NULL,
  `training_data_date` date DEFAULT NULL,
  `evaluation` text COLLATE utf8mb4_unicode_520_ci,
  `license_description` text COLLATE utf8mb4_unicode_520_ci,
  `supported_input_modalities` text COLLATE utf8mb4_unicode_520_ci,
  `supported_output_modalities` text COLLATE utf8mb4_unicode_520_ci,
  `model_schema` text COLLATE utf8mb4_unicode_520_ci,
  `models_publisher_id` bigint unsigned DEFAULT NULL,
  `popularity` float NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_on_slug` (`slug`),
  KEY `index_models_on_visibility_and_slug` (`visibility`,`slug`),
  KEY `index_models_on_has_free_playground_and_visibility` (`has_free_playground`,`visibility`),
  KEY `index_models_on_models_publisher_id` (`models_publisher_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_attachments`;
CREATE TABLE `models_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `guid` binary(16) NOT NULL,
  `uploader_id` bigint unsigned NOT NULL,
  `storage_blob_id` bigint unsigned DEFAULT NULL,
  `state` int NOT NULL DEFAULT '0',
  `size` int NOT NULL,
  `content_type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_attachments_on_guid_and_uploader_id` (`guid`,`uploader_id`),
  KEY `index_models_attachments_on_uploader_id_and_state` (`uploader_id`,`state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_blocks`;
CREATE TABLE `models_blocks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `actor_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `reason` varchar(1024) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `state` tinyint unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_models_blocks_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_key_values`;
CREATE TABLE `models_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_key_values_on_key` (`key`),
  KEY `index_models_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_multipliers`;
CREATE TABLE `models_multipliers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `models_slug` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `input` decimal(10,5) NOT NULL,
  `cached_input` decimal(10,5) DEFAULT NULL,
  `output` decimal(10,5) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_multipliers_on_models_slug` (`models_slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_organization_access_rules`;
CREATE TABLE `models_organization_access_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `allow` tinyint(1) NOT NULL COMMENT 'whether this rule allows or blocks access',
  `models_publisher_id` bigint unsigned DEFAULT NULL COMMENT 'the publisher whose models the rule targets, if any',
  `catalog_item_key` varchar(80) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'the specific model the rule targets, if any',
  `custom_key_id` bigint unsigned DEFAULT NULL COMMENT 'custom key the rule targets, if any',
  `custom_model_id` bigint unsigned DEFAULT NULL COMMENT 'custom model the rule targets, if any',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_on_organization_id_allow_models_publisher_id_011ce96345` (`organization_id`,`allow`,`models_publisher_id`),
  KEY `index_models_organization_access_rules_on_models_publisher_id` (`models_publisher_id`),
  KEY `index_models_organization_access_rules_on_catalog_item_key` (`catalog_item_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_presets`;
CREATE TABLE `models_presets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `slug` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `private` tinyint(1) NOT NULL DEFAULT '1',
  `conversation_history` json DEFAULT NULL,
  `parameters` json NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_presets_on_slug` (`slug`),
  UNIQUE KEY `index_models_presets_on_user_id_and_name` (`user_id`,`name`)
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
DROP TABLE IF EXISTS `models_run_results`;
CREATE TABLE `models_run_results` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `results` json DEFAULT NULL,
  `target_branch` varbinary(1024) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_models_run_results_on_repository_id_and_target_branch` (`repository_id`,`target_branch`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `models_usage_details`;
CREATE TABLE `models_usage_details` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `auths_count` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_models_usage_details_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
