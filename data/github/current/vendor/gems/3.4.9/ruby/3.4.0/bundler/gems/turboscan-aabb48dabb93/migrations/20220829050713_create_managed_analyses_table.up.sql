CREATE TABLE `ts_managed_analyses` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `onboarding_status` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `languages` json NOT NULL,
  `workflows` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_managed_analyses_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
