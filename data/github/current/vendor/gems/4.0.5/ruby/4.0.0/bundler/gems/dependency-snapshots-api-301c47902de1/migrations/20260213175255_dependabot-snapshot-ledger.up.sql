CREATE TABLE `ds_dependabot_events` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `event_type` enum('init','push') NOT NULL,
  `ref` varchar(255) NOT NULL,
  `sha` varchar(64) NOT NULL,
  `push_id` bigint(20) unsigned DEFAULT NULL COMMENT 'the push_id is only expected to have a value for push event_types',
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_dependabot_events_on_repo_event` (`repository_id`, `event_type`, `ref`, `sha`, `push_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `ds_dependabot_requested_snapshots` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `event_id` bigint(20) unsigned NOT NULL COMMENT 'foreign key referring to ds_dependabot_events',
  `ecosystem` varchar(20) NOT NULL,
  `manifest_path_hash` varchar(64) NOT NULL COMMENT 'a SHA-256 representing the manifest path',
  `manifest_path_display` varchar(255) NOT NULL COMMENT 'a bare manifest path for display to users',
  `deadline` datetime NOT NULL COMMENT 'any row with a null received_at after this time is considered missing',
  `snapshot_id` bigint(20) unsigned NULL COMMENT 'the snapshot id received',
  `received_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_request_for_event` (`event_id`,`ecosystem`,`manifest_path_hash`),
  KEY `index_ds_dependabot_requested_snapshots_completeness` (`event_id`, `snapshot_id`, `deadline`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
