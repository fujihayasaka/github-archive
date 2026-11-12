CREATE TABLE `update_config_registries` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `update_config_id` bigint NOT NULL,
  `registry_name` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_update_config_registries_on_config_id_and_name` (`update_config_id`,`registry_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
