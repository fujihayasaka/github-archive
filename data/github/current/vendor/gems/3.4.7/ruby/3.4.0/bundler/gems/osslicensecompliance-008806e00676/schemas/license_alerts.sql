CREATE TABLE IF NOT EXISTS `olc_alerts` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT, 
  `number` int unsigned NOT NULL, -- User-facing alert number for URLs, separate from id
  `status` varchar(32) NOT NULL,
  `resolution` varchar(255) DEFAULT NULL, -- Describes how the alert was resolved (e.g., a policy change, package exception)
  `created_at` datetime(6) NOT NULL, 
  `repository_id` bigint unsigned NOT NULL,
  `organization_id` bigint unsigned NOT NULL,
  `enterprise_id` bigint unsigned DEFAULT NULL,
  `manifest_name` varchar(255) NOT NULL,
  `manifest_line_number` int unsigned NOT NULL,
  `package_ecosystem` int unsigned NOT NULL,
  `package_name` varchar(255) COLLATE utf8mb4_0900_as_cs NOT NULL,
  `package_version` varchar(255) COLLATE utf8mb4_0900_as_cs NOT NULL,
  `spdx_license_expression` varchar(255) NOT NULL,
  `pull_request_number` int unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_olc_alert` (`repository_id`, `number`),
  INDEX `index_organization` (`organization_id`, `status`),
  -- The index below is intended to optimize queries filtering by non-null enterprise_id and status.
  -- Note: Queries filtering for enterprise_id IS NULL will not benefit from this index.
  -- If query patterns change, consider revisiting this index design.
  INDEX `index_enterprise` (`enterprise_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci ROW_FORMAT=DYNAMIC;
