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
