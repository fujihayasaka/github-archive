CREATE TABLE `update_job_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `error_details` text COLLATE utf8mb4_general_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `error_type` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_update_job_errors_on_update_job_id` (`update_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
