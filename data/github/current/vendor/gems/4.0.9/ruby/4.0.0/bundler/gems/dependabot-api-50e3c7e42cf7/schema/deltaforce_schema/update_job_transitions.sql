CREATE TABLE `update_job_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `update_job_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_job_transitions_parent_sort` (`update_job_id`,`sort_key`),
  UNIQUE KEY `index_update_job_transitions_parent_most_recent` (`update_job_id`,`most_recent`),
  KEY `index_update_job_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`),
  KEY `index_per_job_most_recent_and_state` (`update_job_id`,`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
