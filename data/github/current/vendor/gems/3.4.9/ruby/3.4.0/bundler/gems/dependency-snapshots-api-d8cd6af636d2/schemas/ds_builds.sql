CREATE TABLE `ds_builds` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `external_build_id` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `build_type_id` bigint unsigned NOT NULL,
  `scanned_at` datetime DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_ds_builds_on_build_type_id_and_build_id` (`build_type_id`,`external_build_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
