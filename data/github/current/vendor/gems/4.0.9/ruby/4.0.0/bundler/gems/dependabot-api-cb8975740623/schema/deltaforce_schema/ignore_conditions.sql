CREATE TABLE `ignore_conditions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint NOT NULL,
  `dependency_name` varchar(190) COLLATE utf8mb4_general_ci NOT NULL,
  `version_requirement` varchar(190) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `from_config_file` tinyint(1) NOT NULL DEFAULT '0',
  `issue_comment_id` bigint DEFAULT NULL,
  `update_types` json DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_ignored_updates_on_details_to_ignore` (`update_config_id`,`dependency_name`,`version_requirement`),
  KEY `index_ignore_conditions_on_config_and_file` (`update_config_id`,`from_config_file`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
