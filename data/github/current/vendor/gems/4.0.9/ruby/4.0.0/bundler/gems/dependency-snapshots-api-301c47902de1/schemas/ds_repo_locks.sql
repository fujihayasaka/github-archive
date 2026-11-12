CREATE TABLE `ds_repo_locks` (
  `repository_id` bigint unsigned NOT NULL,
  `lock_name` varchar(255) NOT NULL COMMENT 'used to differentiate different lock types',
  `lock_id` char(27) DEFAULT NULL COMMENT 'the unique ksuid of the current lock',
  `expire_at` datetime(3) DEFAULT NULL COMMENT 'a fallback to a perpetually locked process - if the current time is after this value, then the record should be considered unlocked.',
  PRIMARY KEY (`repository_id`,`lock_name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
