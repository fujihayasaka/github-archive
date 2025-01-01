CREATE TABLE `ts_deleted_repositories` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` bigint(20) unsigned NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `delete_finished_at` datetime(6) DEFAULT NULL,
  `db_rows_deleted` bigint(20) unsigned NOT NULL DEFAULT '0',
  `es_docs_deleted` bigint(20) unsigned NOT NULL DEFAULT '0',
  `blobs_deleted` bigint(20) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_deleted_repositories_on_repository_id` (`repository_id`),
  KEY `index_deleted_repositories_on_delete_finished_at` (`delete_finished_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
