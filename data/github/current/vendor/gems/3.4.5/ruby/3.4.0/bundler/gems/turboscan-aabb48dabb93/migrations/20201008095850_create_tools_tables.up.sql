CREATE TABLE `ts_tools` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `guid` varchar(36) NOT NULL,
  `canonical_name` varchar(255) NOT NULL,
  `is_internal_guid` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repository_guid` (`repository_id`,`guid`),
  KEY `index_repository_canonical_name` (`repository_id`,`canonical_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
CREATE TABLE `ts_tool_versions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `tool_id` bigint(20) unsigned NOT NULL,
  `name` varchar(255) NOT NULL,
  `full_name` varchar(255) DEFAULT NULL,
  `version` varchar(255) DEFAULT NULL,
  `semantic_version` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_tool_id` (`tool_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
