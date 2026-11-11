DROP TABLE IF EXISTS `business_in_product_messaging_subscriptions`;
CREATE TABLE `business_in_product_messaging_subscriptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `business_id` bigint unsigned NOT NULL,
  `promotion_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  `tip_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `members_request_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_business_id_093ef7c051` (`business_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ipm_enterprise_matches`;
CREATE TABLE `ipm_enterprise_matches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `enterprise_id` bigint unsigned NOT NULL,
  `cohort` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `metadata` json NOT NULL,
  `day` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ipm_enterprise_matches_ent_cohort_day` (`enterprise_id`,`cohort`,`day`),
  KEY `idx_ipm_enterprise_matches_day_cohort` (`day`,`cohort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ipm_matches`;
CREATE TABLE `ipm_matches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `cohort` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `metadata` json NOT NULL,
  `day` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ipm_matches_user_cohort_day` (`user_id`,`cohort`,`day`),
  KEY `idx_ipm_matches_day_cohort` (`day`,`cohort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ipm_organization_matches`;
CREATE TABLE `ipm_organization_matches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `cohort` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `metadata` json NOT NULL,
  `day` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ipm_organization_matches_org_cohort_day` (`organization_id`,`cohort`,`day`),
  KEY `idx_ipm_organization_matches_day_cohort` (`day`,`cohort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ipm_repository_matches`;
CREATE TABLE `ipm_repository_matches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `cohort` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `metadata` json NOT NULL,
  `day` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_ipm_repository_matches_repo_cohort_day` (`repository_id`,`cohort`,`day`),
  KEY `idx_ipm_repository_matches_day_cohort` (`day`,`cohort`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `org_in_product_messaging_subscriptions`;
CREATE TABLE `org_in_product_messaging_subscriptions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `organization_id` bigint unsigned NOT NULL,
  `promotion_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  `tip_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `members_request_subscribed` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_organization_id_d74d9e5d7b` (`organization_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
