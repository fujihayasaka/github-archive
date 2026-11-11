CREATE TABLE `update_job_unknown_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `error_details` longtext COLLATE utf8mb4_general_ci,
  `error_type` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_unknown_errors_on_update_job_id` (`update_job_id`),
  KEY `idx_uerr_ct_at` (`error_type`,`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
