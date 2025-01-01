CREATE TABLE `ts_tool_versions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `tool_id` bigint unsigned NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `full_name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `version` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `semantic_version` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_codeql_model_pack` boolean NOT NULL DEFAULT false,
  PRIMARY KEY (`id`),
  KEY `index_tool_id` (`tool_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
