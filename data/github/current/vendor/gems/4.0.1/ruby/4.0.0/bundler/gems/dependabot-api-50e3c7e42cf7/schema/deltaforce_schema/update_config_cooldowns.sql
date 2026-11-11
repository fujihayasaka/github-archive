CREATE TABLE `update_config_cooldowns` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint unsigned DEFAULT NULL,
  `default_days` int NOT NULL DEFAULT '0',
  `semver_major_days` int NOT NULL DEFAULT '0',
  `semver_minor_days` int NOT NULL DEFAULT '0',
  `semver_patch_days` int NOT NULL DEFAULT '0',
  `include` json DEFAULT NULL,
  `exclude` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_config_cooldowns_on_config_id` (`update_config_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
