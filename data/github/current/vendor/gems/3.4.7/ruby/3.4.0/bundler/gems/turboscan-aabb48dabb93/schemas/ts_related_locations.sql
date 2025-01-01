CREATE TABLE `ts_related_locations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `file_path` varchar(4096) COLLATE utf8mb4_general_ci NOT NULL,
  `start_line` int unsigned DEFAULT NULL,
  `end_line` int unsigned DEFAULT NULL,
  `start_column` int unsigned DEFAULT NULL,
  `end_column` int unsigned DEFAULT NULL,
  `message` varchar(4096) COLLATE utf8mb4_general_ci NOT NULL,
  `replacement_index` int unsigned NOT NULL,
  `physical_alert_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_related_locations_on_physical_alert_id` (`physical_alert_id`),
  KEY `index_related_locations_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
