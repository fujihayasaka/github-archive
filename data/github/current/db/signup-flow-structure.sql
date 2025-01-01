DROP TABLE IF EXISTS `signup_flow_key_values`;
CREATE TABLE `signup_flow_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_signup_flow_key_values_on_key` (`key`),
  KEY `index_signup_flow_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `user_marketing_consents`;
CREATE TABLE `user_marketing_consents` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'email address used to sign up',
  `country_code` varchar(2) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT '2 character country code of the user',
  `marketing_consent` int DEFAULT NULL COMMENT 'consent to receive marketing emails',
  `onboarding_optout_date` datetime(6) DEFAULT NULL COMMENT 'date the user opted out of onboarding emails',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_user_marketing_consents_on_marketing_consent` (`marketing_consent`),
  KEY `index_user_marketing_consents_on_onboarding_optout_date` (`onboarding_optout_date`),
  KEY `index_user_marketing_consents_on_email` (`email`),
  KEY `index_user_marketing_consents_on_created_at` (`created_at`),
  KEY `index_user_marketing_consents_on_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
