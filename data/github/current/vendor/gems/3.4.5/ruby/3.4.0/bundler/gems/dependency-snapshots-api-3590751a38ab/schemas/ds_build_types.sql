CREATE TABLE `ds_build_types` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint unsigned NOT NULL,
  `external_type_id` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `external_type_id_display` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `detector_name` varchar(255) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'unknown',
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_build_types_on_repo_id_and_external_type_id` (`repository_id`,`external_type_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
