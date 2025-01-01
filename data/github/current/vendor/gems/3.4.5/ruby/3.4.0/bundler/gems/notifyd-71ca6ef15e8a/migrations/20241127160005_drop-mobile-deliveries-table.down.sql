CREATE TABLE IF NOT EXISTS `mobile_notification_deliveries` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `notification_id` varchar(255) NOT NULL,
  `device_token_id` bigint unsigned NOT NULL,
  `state` tinyint(4) unsigned NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_delivery_for_user_notification_and_token` (`user_id`, `notification_id`,`device_token_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
