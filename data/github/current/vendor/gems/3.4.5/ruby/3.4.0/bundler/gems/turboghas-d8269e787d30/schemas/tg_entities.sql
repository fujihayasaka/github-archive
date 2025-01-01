-- cache of a advanced_security_license.billable_owner and its advanced_security_license.user_ids
CREATE TABLE `tg_entities` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `entity_type` enum('Business','User') COLLATE utf8mb4_general_ci NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  `user_ids` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_type` (`entity_type`,`entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
