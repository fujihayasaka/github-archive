DROP TABLE IF EXISTS `apps_key_values`;
CREATE TABLE `apps_key_values` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(255) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_apps_key_values_on_key` (`key`),
  KEY `index_apps_key_values_on_expires_at` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `user_roles`;
CREATE TABLE `user_roles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role_id` bigint unsigned NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `actor_type` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `actor_id` bigint unsigned NOT NULL,
  `conditions` json DEFAULT NULL,
  `conditions_target` varchar(16) COLLATE utf8mb4_unicode_520_ci GENERATED ALWAYS AS (coalesce(json_unquote(json_extract(`conditions`,_utf8mb4'$.target')),_utf8mb4'direct')) VIRTUAL,
  `conditions_target_ids` json GENERATED ALWAYS AS (coalesce(json_extract(`conditions`,_utf8mb4'$.target_ids'))) VIRTUAL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_user_roles_on_role_target_type_actor` (`role_id`,`target_id`,`target_type`,`actor_type`,`actor_id`),
  KEY `idx_user_roles_actor_role_and_target` (`actor_id`,`actor_type`,`role_id`,`target_id`,`target_type`),
  KEY `index_user_roles_on_role_id_and_actor_type_and_actor_id` (`role_id`,`actor_type`,`actor_id`),
  KEY `index_user_roles_on_actor_and_target` (`actor_id`,`actor_type`,`target_id`,`target_type`),
  KEY `index_user_roles_on_target_id_and_target_type_actor_conditions` (`target_id`,`target_type`,`actor_type`,`conditions_target`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
