CREATE TABLE `site_scoped_integration_installations` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `integration_id` bigint unsigned NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_site_scoped_integration_installations_on_integration_id` (`integration_id`),
  KEY `index_site_scoped_integration_installations_on_created_at` (`created_at`),
  KEY `index_site_scoped_integration_installations_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;