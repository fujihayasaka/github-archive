CREATE TABLE `dependency_groups` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL,
  `update_config_id` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `rules` text COLLATE utf8mb4_general_ci,
  `deleted_at` datetime(6) DEFAULT NULL,
  `applies_to` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sort_order` int DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_dependency_groups_on_update_config_id_and_deleted_at` (`update_config_id`,`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
