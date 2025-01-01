CREATE TABLE `ds_snapshots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `snapshot_blob_id` bigint unsigned NOT NULL,
  `source` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sha` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` json DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `scanned_at` datetime NOT NULL,
  `build_id` bigint unsigned NOT NULL,
  `branch_ref` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `internal` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_ds_snapshots_on_repository_id_and_sha` (`repository_id`,`sha`),
  KEY `index_ds_snapshots_on_repository_id_source_and_sha` (`repository_id`,`source`,`sha`),
  KEY `index_ds_snapshots_on_repo_build_id_and_branch_ref` (`repository_id`,`build_id`,`branch_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
