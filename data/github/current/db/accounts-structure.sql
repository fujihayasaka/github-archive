DROP TABLE IF EXISTS `business_intents`;
CREATE TABLE `business_intents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `business_id` bigint unsigned NOT NULL,
  `intent` tinyint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_business_intent` (`business_id`,`intent`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `business_orchestrations`;
CREATE TABLE `business_orchestrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint unsigned DEFAULT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `actor_id` bigint unsigned DEFAULT NULL,
  `type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  `step_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `data_organization_ids` blob,
  `data_team_ids` blob,
  `data_user_ids` blob,
  `data` mediumtext COLLATE utf8mb4_unicode_520_ci,
  `attempts` int NOT NULL DEFAULT '0',
  `error_message` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_type` (`type`,`state`),
  KEY `index_state_updated_at` (`state`,`updated_at`),
  KEY `index_parent_id_state` (`parent_id`,`state`),
  KEY `index_business_id` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `enterprise_team_migrations`;
CREATE TABLE `enterprise_team_migrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `enterprise_team_id` bigint unsigned NOT NULL,
  `team_id` bigint unsigned NOT NULL,
  `migration_status` tinyint unsigned NOT NULL DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_enterprise_team_migrations_on_enterprise_team_id` (`enterprise_team_id`),
  UNIQUE KEY `index_enterprise_team_migrations_on_team_id` (`team_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `team_orchestrations`;
CREATE TABLE `team_orchestrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `parent_id` bigint unsigned DEFAULT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `team_id` bigint unsigned NOT NULL,
  `actor_id` bigint unsigned DEFAULT NULL,
  `type` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `state` int NOT NULL DEFAULT '0',
  `step_name` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `data_organization_ids` mediumblob,
  `data_team_ids` blob,
  `data_user_ids` mediumblob,
  `data` text COLLATE utf8mb4_unicode_520_ci,
  `attempts` int NOT NULL DEFAULT '0',
  `error_message` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_type` (`type`,`state`),
  KEY `index_state_updated_at` (`state`,`updated_at`),
  KEY `index_parent_id_state` (`parent_id`,`state`),
  KEY `index_business_id` (`business_id`),
  KEY `index_team_id` (`team_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
