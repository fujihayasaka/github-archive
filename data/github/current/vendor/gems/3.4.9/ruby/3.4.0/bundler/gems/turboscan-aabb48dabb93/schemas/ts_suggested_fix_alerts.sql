CREATE TABLE `ts_suggested_fix_alerts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `logical_alert_number` bigint unsigned NOT NULL,
  `suggested_fix_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `state` varchar(50) NOT NULL,
  `state_updated_at` datetime(6) NOT NULL,
  `state_updated_actor_id` bigint unsigned DEFAULT NULL,
  `rule_sarif_identifier` varchar(255) NOT NULL,
  `ref_bytes` varbinary(1024) NOT NULL,
  `suggestion_usage` double DEFAULT NULL,
  `requested_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_on_logical_alert_number` (`repository_id`, `logical_alert_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
