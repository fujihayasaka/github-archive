CREATE TABLE `ds_snapshot_blobs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `blob` json NOT NULL,
  `blob_size_bytes` int NOT NULL,
  `created_at` datetime NOT NULL,
  `blob_hash` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `blob_url` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_snapshot_blobs_on_hash` (`blob_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
