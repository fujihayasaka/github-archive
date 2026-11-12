CREATE TABLE `olc_check_jobs` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `status` enum('snapshot_count','waiting','running','pass','fail') NOT NULL,
  `created_at` datetime(6) NOT NULL, -- When this entry was added to the table
  `check_started_at` datetime(6) NOT NULL, -- When the current check started. Gets reset if we get a check request with different SHAs.
  `repository_id` bigint unsigned NOT NULL,
  `organization_id` bigint unsigned NOT NULL,
  `pull_request_id` bigint unsigned NOT NULL,
  `pull_request_number` int unsigned NOT NULL,
  `business_id` bigint unsigned DEFAULT NULL,
  `base_sha` varchar(40) NOT NULL,
  `commit_sha` varchar(40) NOT NULL,
  `expected_snapshots` int unsigned NOT NULL,
  `received_snapshots` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_olc_pr` (`repository_id`,`pull_request_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;