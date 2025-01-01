CREATE TABLE `ts_security_campaign_alerts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `logical_alert_id` bigint unsigned NOT NULL,
  `security_campaign_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_security_campaign_alerts_on_logical_alert_id` (`logical_alert_id`),
  UNIQUE KEY `idx_sc_alerts_on_sc_id_and_repo_id_and_logical_alert_id` (`security_campaign_id`,`repository_id`,`logical_alert_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;