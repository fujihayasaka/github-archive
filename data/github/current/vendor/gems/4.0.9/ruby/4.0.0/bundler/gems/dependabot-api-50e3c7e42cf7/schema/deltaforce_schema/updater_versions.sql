CREATE TABLE `updater_versions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `env` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `ecosystem` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `version` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_updater_versions_on_env_and_ecosystem` (`env`,`ecosystem`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
