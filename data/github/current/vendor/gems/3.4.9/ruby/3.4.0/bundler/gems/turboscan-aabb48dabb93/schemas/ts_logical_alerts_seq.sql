/* Table used to generate the sequential number column on ts_logical_alerts */
CREATE TABLE `ts_logical_alerts_seq` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `number` int unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_logical_alerts_seq_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
