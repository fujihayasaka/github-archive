CREATE TABLE `workflow_jobs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `workflow_build_id` bigint unsigned NOT NULL,
  `external_job_id` varchar(255) COLLATE utf8mb4_bin NOT NULL COMMENT 'The external AZP Job ID',
  `check_run_id` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'The GitHub Check Run ID',
  `check_run_next_id` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL,
  `created_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `workflow_build_execution_id` bigint unsigned DEFAULT NULL,
  `billing_checked` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  KEY `by_external_job_id` (`external_job_id`),
  KEY `by_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
