CREATE TABLE `ts_metric_results` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint(20) unsigned NOT NULL,
  `analysis_id` bigint(20) unsigned NOT NULL,
  `rule_id` bigint(20) unsigned NOT NULL,
  `file_path` varchar(4096) DEFAULT NULL,
  `start_line` int(10) unsigned DEFAULT NULL,
  `end_line` int(10) unsigned DEFAULT NULL,
  `start_column` int(10) unsigned DEFAULT NULL,
  `end_column` int(10) unsigned DEFAULT NULL,
  `value` double NOT NULL,
  `baseline` double DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
