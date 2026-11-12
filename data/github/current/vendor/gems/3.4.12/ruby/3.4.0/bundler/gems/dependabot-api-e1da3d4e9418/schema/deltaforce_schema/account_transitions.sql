CREATE TABLE `account_transitions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `to_state` varchar(150) COLLATE utf8mb4_general_ci NOT NULL,
  `metadata` text COLLATE utf8mb4_general_ci,
  `sort_key` int NOT NULL,
  `account_id` bigint NOT NULL,
  `most_recent` tinyint(1) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `installation_id` bigint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_account_transitions_parent_sort` (`account_id`,`sort_key`),
  UNIQUE KEY `unique_installation_id_across_accounts` (`installation_id`,`account_id`,`sort_key`),
  UNIQUE KEY `index_account_transitions_parent_most_recent` (`account_id`,`most_recent`),
  KEY `index_account_transitions_on_most_recent_and_to_state` (`most_recent`,`to_state`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
