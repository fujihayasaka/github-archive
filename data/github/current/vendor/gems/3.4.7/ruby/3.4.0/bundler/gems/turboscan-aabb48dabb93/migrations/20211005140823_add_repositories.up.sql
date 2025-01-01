CREATE TABLE `ts_repositories` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `owner_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `code_scanning_enabled` tinyint(1) NOT NULL DEFAULT '0',
  `source_updated_at` datetime(6) NOT NULL,
  `default_ref` varbinary(1024) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repositories_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
