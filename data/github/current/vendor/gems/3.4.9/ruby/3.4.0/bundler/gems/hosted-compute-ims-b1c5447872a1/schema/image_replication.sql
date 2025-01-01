CREATE TABLE `image_replication` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `image_definition_id` bigint unsigned NOT NULL,
  `image_version` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `replication_data` text COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `by_id_version` (`image_definition_id`,`image_version`) COMMENT 'Unique constraint to ensure that there is only one image replication dataset per image_id and image_version'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;