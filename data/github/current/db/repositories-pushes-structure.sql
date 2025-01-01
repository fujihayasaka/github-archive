DROP TABLE IF EXISTS `authentic_commits`;
CREATE TABLE `authentic_commits` (
  `network_id` bigint unsigned NOT NULL,
  `oid` binary(20) NOT NULL,
  `verified_at` datetime(6) NOT NULL,
  PRIMARY KEY (`network_id`,`oid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `pushes`;
CREATE TABLE `pushes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned DEFAULT NULL,
  `pusher_id` bigint unsigned DEFAULT NULL,
  `before` varchar(40) DEFAULT NULL,
  `after` varchar(40) DEFAULT NULL,
  `ref` varbinary(1024) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime DEFAULT NULL,
  `pushed_at` datetime(6) NOT NULL,
  `push_type` tinyint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_pushes_on_repository_id_and_after` (`repository_id`,`after`),
  KEY `index_pushes_on_repository_id_and_ref_and_pushed_at` (`repository_id`,`ref`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_pusher_id_and_pushed_at` (`repository_id`,`pusher_id`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_pushed_at` (`repository_id`,`pushed_at`),
  KEY `index_pushes_on_repository_id_and_push_type_and_pushed_at` (`repository_id`,`push_type`,`pushed_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;
DROP TABLE IF EXISTS `ref_pushes`;
CREATE TABLE `ref_pushes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `pusher_id` bigint unsigned NOT NULL,
  `ref` varbinary(1024) NOT NULL,
  `after` varchar(40) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `pushed_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ref_pushes_on_repository_id_and_pusher_id_and_ref` (`repository_id`,`pusher_id`,`ref`),
  UNIQUE KEY `index_ref_pushes_on_repository_id_and_ref_and_pusher_id` (`repository_id`,`ref`,`pusher_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ref_updates`;
CREATE TABLE `ref_updates` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `push_id` bigint unsigned NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `before_oid` binary(20) NOT NULL,
  `after_oid` binary(20) NOT NULL,
  `ref` varbinary(1024) NOT NULL,
  `ref_update_type` tinyint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ref_updates_on_repository_id_and_after_oid` (`repository_id`,`after_oid`),
  KEY `index_ref_updates_on_repository_id_and_ref` (`repository_id`,`ref`),
  KEY `index_ref_updates_on_repository_id_and_ref_update_type` (`repository_id`,`ref_update_type`),
  KEY `index_ref_updates_on_push_id` (`push_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
DROP TABLE IF EXISTS `ref_updates_id_ks_idx`;
CREATE TABLE `ref_updates_id_ks_idx` (
  `id` bigint unsigned NOT NULL,
  `keyspace_id` varbinary(128) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
