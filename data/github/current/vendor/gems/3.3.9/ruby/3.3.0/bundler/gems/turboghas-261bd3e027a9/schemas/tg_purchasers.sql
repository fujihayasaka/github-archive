CREATE TABLE `tg_purchasers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `entity_type` enum('Business','User') COLLATE utf8mb4_general_ci NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `owner_id` (`owner_id`),
  KEY `idx_purchasers_entity` (`entity_type`,`entity_id`,`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
