CREATE TABLE `config_file_errors` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `repo_id` bigint NOT NULL,
  `error_details` text COLLATE utf8mb4_general_ci,
  `error_type` varchar(60) COLLATE utf8mb4_general_ci NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_rails_0d1aa35a98` (`repo_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
