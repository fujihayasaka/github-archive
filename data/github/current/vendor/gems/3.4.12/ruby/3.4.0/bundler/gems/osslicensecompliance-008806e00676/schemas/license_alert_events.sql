CREATE TABLE IF NOT EXISTS `olc_alert_events` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `alert_id` bigint unsigned NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `occurred_at` datetime(6) NOT NULL,
  `event_body` JSON NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_olc_event` (`alert_id`, `event_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
