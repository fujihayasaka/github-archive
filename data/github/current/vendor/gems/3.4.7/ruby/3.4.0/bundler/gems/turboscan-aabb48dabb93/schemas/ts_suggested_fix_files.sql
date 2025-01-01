CREATE TABLE `ts_suggested_fix_files` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `suggested_fix_id` bigint unsigned NOT NULL,
  `file_path` varchar(4096) COLLATE utf8mb4_general_ci NOT NULL,
  `file_path_hash` binary(32) NOT NULL,
  `file_checksum` binary(20) NOT NULL,
  `diff_content` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_fix_files_on_repository_id_and_suggesting_fix_id` (`repository_id`, `suggested_fix_id`, `file_path_hash`, `file_checksum`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
