CREATE TABLE `accounts` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_id` bigint NOT NULL,
  `github_login` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `account_type` varchar(10) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `create_merge_commits` tinyint(1) NOT NULL,
  `initial_update_runs_pr_limit` int DEFAULT NULL,
  `merge_on_approval` tinyint(1) NOT NULL,
  `unlimited_private_repos_override` tinyint(1) NOT NULL,
  `allow_automerging` tinyint(1) NOT NULL,
  `event_source` int NOT NULL DEFAULT '0',
  `tenant_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_accounts_on_github_id_and_account_type` (`github_id`,`account_type`),
  KEY `index_accounts_on_github_login` (`github_login`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
