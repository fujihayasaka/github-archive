CREATE TABLE `ts_alert_links` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `logical_alert_id` bigint unsigned NOT NULL,
  `ref` varbinary(1024) DEFAULT NULL,
  `pull_request_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_alert_links_on_repo_id_and_logical_alert_id` (`repository_id`,`logical_alert_id`),
  KEY `index_alert_links_on_repo_id_and_ref` (`repository_id`,`ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
