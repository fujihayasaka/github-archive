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
CREATE TABLE `tg_entities` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `entity_type` enum('Business','User') COLLATE utf8mb4_general_ci NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  `user_ids` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `entity_type` (`entity_type`,`entity_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `tg_purchasers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `owner_id` bigint unsigned NOT NULL,
  `entity_type` enum('Business','User') COLLATE utf8mb4_general_ci NOT NULL,
  `entity_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `owner_id` (`owner_id`),
  KEY `idx_purchasers_entity` (`entity_type`,`entity_id`,`owner_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
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
CREATE TABLE `tg_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `login` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `type` enum('Organization','User') COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `user_id` (`user_id`),
  KEY `idx_users_login` (`login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
