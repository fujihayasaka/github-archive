CREATE TABLE `scoped_integration_installations` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `integration_installation_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_scoped_installations_on_integration_installation_id` (`integration_installation_id`),
  KEY `index_scoped_integration_installations_on_created_at` (`created_at`),
  KEY `index_scoped_integration_installations_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;