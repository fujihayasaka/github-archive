CREATE TABLE `routing_setting_custom_fields` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `meta_id` bigint unsigned NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `value` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_routing_setting_custom_fields_user_id_meta_id_name_value` (`user_id`,`meta_id`,`name`,`value`),
  UNIQUE KEY `unique_routing_setting_custom_fields_name_value_meta_id` (`name`,`value`,`meta_id`),
  KEY `idx_routing_setting_custom_fields_meta_id_name_value` (`meta_id`,`name`,`value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
