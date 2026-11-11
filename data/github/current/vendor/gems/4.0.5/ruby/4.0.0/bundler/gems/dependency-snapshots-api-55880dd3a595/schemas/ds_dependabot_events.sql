CREATE TABLE `ds_dependabot_events` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `event_type` enum('init','push') COLLATE utf8mb4_general_ci NOT NULL,
  `ref` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `sha` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `push_id` bigint unsigned DEFAULT NULL COMMENT 'the push_id is only expected to have a value for push event_types',
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_dependabot_events_on_repo_event` (`repository_id`,`event_type`,`ref`,`sha`,`push_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
