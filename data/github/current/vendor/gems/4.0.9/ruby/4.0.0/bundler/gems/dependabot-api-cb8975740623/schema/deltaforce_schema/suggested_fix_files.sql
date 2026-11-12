CREATE TABLE `suggested_fix_files` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `suggested_fix_id` bigint NOT NULL,
  `file_path` varchar(4096) COLLATE utf8mb4_general_ci NOT NULL,
  `file_path_hash` varbinary(32) NOT NULL,
  `file_checksum` varbinary(20) NOT NULL,
  `diff_content` blob NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_suggested_fix_files_on_suggested_fix_id` (`suggested_fix_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
