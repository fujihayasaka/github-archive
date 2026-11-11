CREATE TABLE `pending_pull_request_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `pending_pull_request_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_pending_pull_request_transitions_parent_sort` (`pending_pull_request_id`,`sort_key`),
  UNIQUE KEY `index_pending_pull_request_transitions_parent_most_recent` (`pending_pull_request_id`,`most_recent`),
  KEY `index_pending_prs_on_most_recent_and_to_state` (`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
