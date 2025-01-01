-- commits made against advanced security eligible repositories
CREATE TABLE `tg_contributions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `pushed_at` date NOT NULL,
  `email` varbinary(255) NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  UNIQUE KEY `repository_id` (`repository_id`,`user_id`),
  KEY `idx_repository_id_user_id_pushed_at` (`repository_id`,`user_id`,`pushed_at`),
  KEY `idx_repository_id_pushed_at` (`repository_id`,`pushed_at`),
  KEY `idx_user_id_pushed_at` (`user_id`,`pushed_at`),
  KEY `idx_contributions_pushed_at` (`pushed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
