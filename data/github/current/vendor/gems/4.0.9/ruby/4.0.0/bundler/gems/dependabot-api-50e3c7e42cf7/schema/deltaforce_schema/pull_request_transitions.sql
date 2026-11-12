CREATE TABLE `pull_request_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `pull_request_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `update_job_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pull_request_transitions_parent_sort` (`pull_request_id`,`sort_key`),
  UNIQUE KEY `index_pull_request_transitions_parent_most_recent` (`pull_request_id`,`most_recent`),
  KEY `index_pull_request_transitions_on_update_job_id` (`update_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
