CREATE TABLE `tg_meter_emissions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `customer_id` bigint unsigned NOT NULL,
  `actor_id` bigint unsigned NOT NULL,
  `sku` tinyint NOT NULL,
  `usage_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `customer_actor_sku` (`customer_id`,`actor_id`,`sku`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
