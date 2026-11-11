CREATE TABLE `ds_dependabot_requested_snapshots` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `event_id` bigint unsigned NOT NULL COMMENT 'foreign key referring to ds_dependabot_events',
  `ecosystem` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `manifest_path_hash` varchar(64) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'a SHA-256 representing the manifest path',
  `manifest_path_display` varchar(255) COLLATE utf8mb4_general_ci NOT NULL COMMENT 'a bare manifest path for display to users',
  `deadline` datetime NOT NULL COMMENT 'any row with a null received_at after this time is considered missing',
  `snapshot_id` bigint unsigned DEFAULT NULL COMMENT 'the snapshot id received',
  `received_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_request_for_event` (`event_id`,`ecosystem`,`manifest_path_hash`),
  KEY `index_ds_dependabot_requested_snapshots_completeness` (`event_id`,`snapshot_id`,`deadline`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
