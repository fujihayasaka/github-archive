CREATE TABLE `ts_analysis_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `analysis_id` bigint unsigned NOT NULL,
  `rule_id` bigint unsigned NOT NULL,
  -- the tool component that defined this rule, 0 if unknown
  `defining_tool_version_id` bigint unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_analysis_rules_repo_analysis` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
