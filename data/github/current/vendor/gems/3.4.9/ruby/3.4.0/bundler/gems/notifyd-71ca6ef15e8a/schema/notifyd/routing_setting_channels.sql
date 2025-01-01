CREATE TABLE `routing_setting_channels` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `routing_setting_id` bigint NOT NULL,
  `channel` varchar(20) COLLATE utf8mb4_unicode_ci NOT NULL,
  `enabled` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_routing_setting_channels_rs_id_with_channel` (`routing_setting_id`,`channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
