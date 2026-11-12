CREATE TABLE `pending_pull_requests` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_job_id` bigint NOT NULL,
  `updated_dependency_details` mediumtext COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `sort_key` int NOT NULL,
  `grouped_update` tinyint(1) DEFAULT '0',
  `dependency_group_id` bigint DEFAULT NULL,
  `current_state` varchar(40) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pending_pull_requests_parent_sort` (`update_job_id`,`sort_key`),
  KEY `index_pending_pull_requests_on_created_at` (`created_at`),
  KEY `index_pending_pull_requests_on_current_state_and_update_job_id` (`current_state`,`update_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
