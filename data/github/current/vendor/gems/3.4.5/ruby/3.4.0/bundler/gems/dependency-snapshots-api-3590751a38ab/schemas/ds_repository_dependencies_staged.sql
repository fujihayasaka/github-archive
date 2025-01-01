CREATE TABLE `ds_repository_dependencies_staged` (
  `repository_id` bigint unsigned NOT NULL,
  `staged` bit(1) NOT NULL DEFAULT b'0',
  `dependency_locator` varchar(300) COLLATE utf8mb4_general_ci NOT NULL,
  `dependency_version` varchar(256) COLLATE utf8mb4_general_ci NOT NULL,
  `purl` varchar(512) COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`repository_id`,`staged`,`dependency_locator`,`dependency_version`),
  KEY `dependency_locator` (`dependency_locator`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
