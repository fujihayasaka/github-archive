-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_tools` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `guid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `canonical_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `is_internal_guid` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_guid` (`guid`),
  KEY `index_canonical_name` (`canonical_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
