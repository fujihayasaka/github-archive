CREATE TABLE `pending_pull_request_updates` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `updated_base_commit_sha` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
