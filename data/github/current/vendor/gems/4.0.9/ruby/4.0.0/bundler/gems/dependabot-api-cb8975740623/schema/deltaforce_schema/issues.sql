CREATE TABLE `issues` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `github_number` bigint NOT NULL,
  `update_job_id` bigint DEFAULT NULL,
  `repo_id` bigint NOT NULL,
  `issue_type` varchar(60) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `issue_detail` text COLLATE utf8mb4_general_ci,
  `update_config_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_issues_on_repo_id_and_github_number` (`repo_id`,`github_number`),
  KEY `index_issues_on_update_job_id` (`update_job_id`),
  KEY `index_issues_on_update_config_id` (`update_config_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
