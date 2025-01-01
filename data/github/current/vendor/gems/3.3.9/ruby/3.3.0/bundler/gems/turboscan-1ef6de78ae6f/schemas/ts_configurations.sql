CREATE TABLE `ts_configurations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `ref` varbinary(1024) NOT NULL,
  `tool_id` bigint unsigned NOT NULL,
  `category` varchar(1000) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `hash` binary(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_configurations_unique` (`hash`),
  KEY `index_configurations_on_repository_id` (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
