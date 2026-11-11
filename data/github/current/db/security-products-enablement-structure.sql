DROP TABLE IF EXISTS `code_scanning_assessment_repositories`;
CREATE TABLE `code_scanning_assessment_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `assessment_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `status` tinyint unsigned NOT NULL,
  `failure_reason` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `workflow_id` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `supported_languages` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_assessment_id_and_repository_id` (`assessment_id`,`repository_id`),
  KEY `index_assessment_id_and_status` (`assessment_id`,`status`),
  KEY `index_status_and_created_at` (`status`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `code_scanning_assessment_results`;
CREATE TABLE `code_scanning_assessment_results` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `assessment_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `rule_id` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rule_name` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `language` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `autofix_supported` tinyint(1) NOT NULL DEFAULT '0',
  `severity` varchar(12) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `vulnerability_count` int NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_csra_results_unique` (`assessment_id`,`repository_id`,`rule_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `code_scanning_assessments`;
CREATE TABLE `code_scanning_assessments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `number` int unsigned NOT NULL,
  `requested_by_id` bigint unsigned NOT NULL,
  `status` tinyint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_owner_id_and_number` (`owner_id`,`number`),
  KEY `index_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `pre_ghas_sku_trial_enabled_repositories`;
CREATE TABLE `pre_ghas_sku_trial_enabled_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sku_name` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_target_id_and_sku_name_and_repository_id` (`target_id`,`target_type`,`sku_name`,`repository_id`),
  KEY `index_pre_ghas_sku_trial_enabled_repositories_on_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `pre_ghas_trial_default_private_repo_security_configurations`;
CREATE TABLE `pre_ghas_trial_default_private_repo_security_configurations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `security_configuration_id` bigint unsigned NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `billing_entity_id` bigint unsigned NOT NULL,
  `billing_entity_type` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sku_name` varchar(80) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `trial_type` tinyint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_target_id_target_type_sku_name_security_config_id` (`target_id`,`target_type`,`sku_name`,`security_configuration_id`),
  KEY `index_billing_entity_and_sku_name` (`billing_entity_id`,`billing_entity_type`,`sku_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `repository_security_settings`;
CREATE TABLE `repository_security_settings` (
  `repository_id` bigint unsigned NOT NULL,
  `feature` tinyint unsigned NOT NULL,
  `state` tinyint NOT NULL,
  `blocker` tinyint DEFAULT NULL,
  `failure` tinyint DEFAULT NULL,
  PRIMARY KEY (`repository_id`,`feature`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `security_configuration_attachments`;
CREATE TABLE `security_configuration_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `bulk_attachment_id` bigint unsigned DEFAULT NULL,
  `security_configuration_id` bigint unsigned NOT NULL,
  `security_configuration_version` int unsigned NOT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `actor_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `attachment_options` json NOT NULL,
  `state` tinyint unsigned NOT NULL DEFAULT '0',
  `state_reason` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_attachments_on_bulk_attachment_id_and_state` (`bulk_attachment_id`,`state`),
  KEY `index_attachments_on_state_and_updated_at` (`state`,`updated_at`),
  KEY `index_attachments_on_security_configuration_id` (`security_configuration_id`),
  KEY `index_attachments_on_business_id` (`business_id`),
  KEY `index_attachments_on_owner_id` (`owner_id`),
  KEY `index_attachments_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `security_configuration_bulk_attachments`;
CREATE TABLE `security_configuration_bulk_attachments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint unsigned DEFAULT NULL,
  `security_configuration_id` bigint unsigned NOT NULL,
  `security_configuration_version` int unsigned NOT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `actor_id` bigint unsigned NOT NULL,
  `repository_selection` json NOT NULL,
  `attachment_options` json NOT NULL,
  `state` tinyint unsigned NOT NULL DEFAULT '0',
  `state_reason` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `staging_cursor` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `staging_attempt` int unsigned NOT NULL DEFAULT '0',
  `attachment_progress` json NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_bulk_attachments_on_state_and_updated_at` (`state`,`updated_at`),
  KEY `index_bulk_attachments_on_parent_id_and_state` (`parent_id`,`state`),
  KEY `index_bulk_attachments_on_security_configuration_id` (`security_configuration_id`),
  KEY `index_bulk_attachments_on_business_id` (`business_id`),
  KEY `index_bulk_attachments_on_owner_id` (`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `security_products_enablement_repositories`;
CREATE TABLE `security_products_enablement_repositories` (
  `repository_id` bigint unsigned NOT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `security_configuration_id` bigint unsigned DEFAULT NULL,
  `security_configuration_state` tinyint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`repository_id`),
  KEY `index_on_owner_and_config` (`owner_id`,`security_configuration_id`,`security_configuration_state`),
  KEY `index_on_business_and_config` (`business_id`,`security_configuration_id`,`security_configuration_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
