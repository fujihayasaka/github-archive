CREATE TABLE `ts_suggested_fixes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `ai_version` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ai_model` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` text NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `dependency_metadata` json DEFAULT NULL,
  `problems` json DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
