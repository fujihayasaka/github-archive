CREATE TABLE `authentication_tokens` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `authenticatable_id` bigint NOT NULL,
  `authenticatable_type` enum('IntegrationInstallation','ScopedIntegrationInstallation','SiteScopedIntegrationInstallation') COLLATE utf8mb3_general_ci NOT NULL,
  `hashed_value` varbinary(44) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `token_last_eight` char(8) DEFAULT NULL,
  `expires_at_timestamp` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_authentication_tokens_on_hashed_value` (`hashed_value`),
  KEY `index_authentication_tokens_on_authenticatable_id_and_type` (`authenticatable_id`,`authenticatable_type`),
  KEY `index_authentication_tokens_on_expires_at_timestamp` (`expires_at_timestamp`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;