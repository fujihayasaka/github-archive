-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_rules` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  -- Identifies the SARIF 'driver' tool component
  `tool_id` bigint unsigned NOT NULL,
  `sarif_identifier` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `short_description` text COLLATE utf8mb4_general_ci,
  `full_description` text COLLATE utf8mb4_general_ci,
  `help_uri` varchar(1024) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `help` mediumtext COLLATE utf8mb4_general_ci,
  `severity_level` tinyint unsigned NOT NULL,
  `security_severity` double DEFAULT NULL,
  `precision` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `precision_level` tinyint unsigned NOT NULL DEFAULT '0',
  `deprecated_ids` json DEFAULT NULL,
  `query_uri` varchar(1024) COLLATE utf8mb4_general_ci NOT NULL,
  `hash` binary(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_tool_id_sarif_hash` (`tool_id`,`sarif_identifier`,`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
