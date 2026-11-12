CREATE TABLE `ds_repository_denormalization_snapshots` (
  `repository_id` bigint(20) unsigned NOT NULL,
  `snapshots_hash` varchar(64) DEFAULT NULL,
  PRIMARY KEY (`repository_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
