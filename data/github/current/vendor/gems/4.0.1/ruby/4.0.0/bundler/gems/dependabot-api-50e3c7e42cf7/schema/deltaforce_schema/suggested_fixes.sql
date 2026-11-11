CREATE TABLE `suggested_fixes` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `autofix_suggestion_job_id` bigint NOT NULL,
  `description` text COLLATE utf8mb4_general_ci,
  `ai_version` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `ai_model` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `dependency_metadata` json DEFAULT NULL,
  `review_status` int DEFAULT '0',
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_suggested_fixes_on_autofix_suggestion_job_id` (`autofix_suggestion_job_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
