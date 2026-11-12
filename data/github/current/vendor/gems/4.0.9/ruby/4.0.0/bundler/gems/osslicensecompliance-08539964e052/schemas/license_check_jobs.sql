CREATE TABLE `olc_check_jobs` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `status` varchar(10) NOT NULL,
  `created_at` datetime(6) NOT NULL, -- When this entry was added to the table
  `check_started_at` datetime(6) NOT NULL, -- When the current check started. Gets reset if we get a check request with different SHAs.
  `repository_id` bigint unsigned NOT NULL,
  `organization_id` bigint unsigned NOT NULL,
  `pull_request_id` bigint unsigned NOT NULL,
  `pull_request_number` int unsigned NOT NULL,
  `enterprise_id` bigint unsigned DEFAULT NULL,
  `fork_repository_id` bigint unsigned DEFAULT NULL,
  `base_sha` varchar(40) NOT NULL,
  `commit_sha` varchar(40) NOT NULL,
  `expected_snapshots` int unsigned NOT NULL,
  `received_snapshots` int unsigned NOT NULL,
  `missing_detectors` json NOT NULL DEFAULT (JSON_ARRAY()), -- Detectors we are still waiting on snapshots from while in Waiting status. Cleared when all snapshots are received. Useful for stafftools diagnostics.
  `dependabot_pending` tinyint(1) NOT NULL DEFAULT 0, -- Whether we are waiting for Dependabot incremental snapshots. Set from DS-API's GetSnapshotDiffStatus response.
  `head_ref` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL, -- Fully-qualified head ref (e.g. refs/heads/main). Nullable for rows created before this column was added. Shape matches ds-api's branch_ref column.
  `base_ref` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL, -- Fully-qualified base branch ref (e.g. refs/heads/main). Nullable for rows created before this column was added. Shape matches ds-api's branch_ref column. Used by snapshot-processed event matching to wake waiting checks when a Dependabot snapshot is submitted for the PR's base branch.
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_olc_pr` (`repository_id`,`pull_request_number`),
  INDEX `check_start_idx` (`check_started_at`),
  INDEX `commit_sha_idx` (`commit_sha`),
  INDEX `head_ref_idx` (`repository_id`,`head_ref`),
  INDEX `base_ref_idx` (`repository_id`,`base_ref`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
