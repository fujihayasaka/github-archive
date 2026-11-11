CREATE TABLE `update_job_warnings` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `warn_type` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `warn_title` varchar(256) COLLATE utf8mb4_general_ci NOT NULL,
  `warn_description` text COLLATE utf8mb4_general_ci,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_warnings_on_update_job_id` (`update_job_id`),
  KEY `idx_ujwarns_ct_at` (`warn_type`,`warn_title`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
