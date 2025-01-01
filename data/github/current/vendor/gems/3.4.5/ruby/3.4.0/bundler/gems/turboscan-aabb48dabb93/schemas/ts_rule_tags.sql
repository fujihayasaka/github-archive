-- ATTENTION: This table is included in an airflow definition. Any table or
-- column name change must be reflected there.
CREATE TABLE `ts_rule_tags` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `rule_id` bigint unsigned NOT NULL,
  `tag` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_rule_id_tag` (`rule_id`,`tag`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
