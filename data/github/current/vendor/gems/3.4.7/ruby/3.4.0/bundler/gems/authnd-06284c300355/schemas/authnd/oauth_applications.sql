-- Tracks a vestigial table on the authnd-production cluster.  Not used for dev/test/CI.
CREATE TABLE `oauth_applications` (
  `id` int(11) NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `state` int(11) DEFAULT '0',
  `sync_timestamp` datetime NOT NULL,
  `sync_kafka_offset` bigint(20) NOT NULL,
  `sync_binlog_position` varchar(255) NOT NULL,
  `sync_gtid_position` varchar(255) NOT NULL,
  `sync_state` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_oauth_applications_on_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
