-- cache of the repositories table
CREATE TABLE `tg_repositories` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `repository_id` (`repository_id`),
  KEY `idx_repositories_owner_id_name` (`owner_id`,`name`),
  KEY `idx_repositories_owner_id_repository_id` (`owner_id`,`repository_id`),
  KEY `idx_repositories_updated_at` (`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
