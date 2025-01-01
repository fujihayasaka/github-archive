CREATE TABLE `ds_canonical_snapshots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint NOT NULL,
  `build_type_id` int NOT NULL,
  `snapshot_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `updated_stamp` timestamp(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  `stale_since` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_repo_build_ref` (`repository_id`,`build_type_id`),
  KEY `index_ds_canonical_snapshots_on_repo_build_ref` (`repository_id`,`build_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
