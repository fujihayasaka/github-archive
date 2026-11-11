CREATE TABLE `tenants` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `slug` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `github_id` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `shortcode` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_tenants_on_github_id` (`github_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
