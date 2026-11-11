CREATE TABLE `updated_dependencies` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `name` varchar(190) COLLATE utf8mb4_general_ci NOT NULL,
  `version` varchar(190) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `package_manager` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `previous_version` varchar(190) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `requirements` text COLLATE utf8mb4_general_ci,
  `previous_requirements` text COLLATE utf8mb4_general_ci,
  `non_breaking_if_semver` tinyint(1) NOT NULL,
  `removed` tinyint(1) NOT NULL DEFAULT '0',
  `directory` varbinary(1024) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_updated_dependencies_on_pr_id_and_dependency_details` (`pull_request_id`,`name`,`package_manager`,`version`,`previous_version`),
  KEY `index_updated_dependencies_on_dependency_details_and_pr_id` (`name`,`package_manager`,`version`,`previous_version`,`pull_request_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
