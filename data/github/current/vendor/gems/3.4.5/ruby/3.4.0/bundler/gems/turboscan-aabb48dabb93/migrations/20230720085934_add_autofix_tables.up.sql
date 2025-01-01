CREATE TABLE `ts_suggested_fix_alerts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `physical_alert_id` bigint unsigned NOT NULL,
  `logical_alert_number` bigint unsigned NOT NULL,
  `suggested_fix_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_on_physical_alert_id` (`physical_alert_id`),
  KEY `idx_on_logical_alert_number` (`repository_id`, `logical_alert_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_suggested_fix_files` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `suggested_fix_id` bigint unsigned NOT NULL,
  `file_path` varchar(4096) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `file_sum` varchar(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `diff_content` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_fix_files_on_repository_id_and_suggesting_fix_id` (`repository_id`,`suggested_fix_id`),
  KEY `idx_suggested_fix_file_sum` (`suggested_fix_id`,`file_sum`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_suggested_fixes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `dismissed` tinyint(1) NOT NULL DEFAULT '0',
  `ai_version` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ai_model` varchar(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` text COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
