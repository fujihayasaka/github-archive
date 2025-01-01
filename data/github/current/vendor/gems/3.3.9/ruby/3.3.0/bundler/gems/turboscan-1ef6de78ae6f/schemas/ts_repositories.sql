CREATE TABLE `ts_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `code_scanning_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `source_updated_at` datetime(6) NOT NULL,
  `default_ref` varbinary(1024) NOT NULL,
  `visibility` enum('public','private','internal') COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_indexed_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repositories_on_repository_id` (`repository_id`),
  KEY `index_repositories_on_last_indexed_at` (`last_indexed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
