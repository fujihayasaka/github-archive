CREATE TABLE `ds_repository_denormalization_locks` (
  `repository_id` bigint unsigned NOT NULL,
  PRIMARY KEY (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
