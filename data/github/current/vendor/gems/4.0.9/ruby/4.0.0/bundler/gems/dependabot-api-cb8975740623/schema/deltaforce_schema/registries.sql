CREATE TABLE `registries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `registry_type` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `credentials` json NOT NULL,
  `source_type` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `source_id` bigint NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_source_name` (`source_type`,`source_id`,`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
