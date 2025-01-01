CREATE TABLE `ts_branch_protection_rules` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `rule_eid` bigint(20) unsigned NOT NULL,
  `pattern` varbinary(1024) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_on_repository_id_rule_eid` (`repository_id`,`rule_eid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
