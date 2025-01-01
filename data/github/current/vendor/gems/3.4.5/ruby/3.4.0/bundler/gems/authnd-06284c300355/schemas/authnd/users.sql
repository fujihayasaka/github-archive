-- Tracks a vestigial table on the authnd-production cluster.  Not used for dev/test/CI.
CREATE TABLE `users` (
  `id` int(11) NOT NULL,
  `login` varchar(40) NOT NULL,
  `bcrypt_auth_token` varchar(60) DEFAULT NULL,
  `password_hash` varbinary(127) DEFAULT NULL,
  `weak_password_check_result` varbinary(128) DEFAULT NULL,
  `token_secret` varchar(40) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `suspended_at` datetime DEFAULT NULL,
  `disabled` tinyint(1) DEFAULT '0',
  `sync_timestamp` datetime NOT NULL,
  `sync_kafka_offset` bigint(20) NOT NULL,
  `sync_binlog_position` varchar(255) NOT NULL,
  `sync_gtid_position` varchar(255) NOT NULL,
  `sync_state` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;