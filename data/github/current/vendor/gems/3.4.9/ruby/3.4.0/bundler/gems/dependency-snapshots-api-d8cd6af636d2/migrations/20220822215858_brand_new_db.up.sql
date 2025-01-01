CREATE TABLE `ds_repository_dependencies_staged` (
  `repository_id` bigint(20) unsigned NOT NULL,
  `staged` bit(1) NOT NULL DEFAULT b'0',
  `dependency_locator` varchar(300) NOT NULL,
  `dependency_version` varchar(256) NOT NULL,
  `purl` varchar(512) NOT NULL,
  PRIMARY KEY (`repository_id`,`staged`,`dependency_locator`,`dependency_version`),
  KEY `dependency_locator` (`dependency_locator`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_build_types` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `external_type_id` varchar(255) DEFAULT NULL,
  `external_type_id_display` varchar(255) DEFAULT NULL,
  `detector_name` varchar(255) NOT NULL DEFAULT 'unknown',
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_build_types_on_repo_id_and_external_type_id` (`repository_id`,`external_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_builds` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `external_build_id` varchar(255) DEFAULT NULL,
  `build_type_id` bigint(20) unsigned NOT NULL,
  `scanned_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_builds_on_build_type_id_and_build_id` (`build_type_id`,`external_build_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_canonical_snapshots` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) NOT NULL,
  `build_type_id` int(10) NOT NULL,
  `snapshot_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `updated_stamp` timestamp(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6) ON UPDATE CURRENT_TIMESTAMP(6),
  `stale_since` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_repo_build_ref` (`repository_id`,`build_type_id`),
  KEY `index_ds_canonical_snapshots_on_repo_build_ref` (`repository_id`,`build_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_repository_denormalization_locks` (
  `repository_id` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_snapshot_blobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `blob` json NOT NULL,
  `blob_size_bytes` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `blob_hash` varchar(128) DEFAULT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `blob_url` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_snapshot_blobs_on_hash` (`blob_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ds_snapshots` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `snapshot_blob_id` bigint(20) unsigned NOT NULL,
  `source` varchar(255) DEFAULT NULL,
  `sha` varchar(64) NOT NULL,
  `metadata` json DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `scanned_at` datetime NOT NULL,
  `build_id` bigint(20) unsigned NOT NULL,
  `branch_ref` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_snapshots_on_repository_id_and_sha` (`repository_id`,`sha`),
  KEY `index_ds_snapshots_on_repository_id_source_and_sha` (`repository_id`,`source`,`sha`),
  KEY `index_ds_snapshots_on_repo_build_id_and_branch_ref` (`repository_id`,`build_id`,`branch_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
