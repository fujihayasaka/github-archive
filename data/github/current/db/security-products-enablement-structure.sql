DROP TABLE IF EXISTS `repository_security_settings`;
CREATE TABLE `repository_security_settings` (
  `repository_id` bigint unsigned NOT NULL,
  `feature` tinyint unsigned NOT NULL,
  `state` tinyint NOT NULL,
  `blocker` tinyint DEFAULT NULL,
  `failure` tinyint DEFAULT NULL,
  PRIMARY KEY (`repository_id`,`feature`)
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
