-- Tracks a vestigial table on the authnd-production cluster.  Not used for dev/test/CI.
CREATE TABLE `integration_installations` (
  `id` bigint(20) NOT NULL,
  `integration_id` int(11) NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(30) NOT NULL,
  `created_at` datetime NOT NULL,
  `integration_version_id` int(11) NOT NULL,
  `user_suspended_by_id` int(11) DEFAULT NULL,
  `user_suspended_at` bigint(20) DEFAULT NULL,
  `integrator_suspended` tinyint(1) NOT NULL DEFAULT '0',
  `integrator_suspended_at` bigint(20) DEFAULT NULL,
  `sync_timestamp` datetime NOT NULL,
  `sync_kafka_offset` bigint(20) NOT NULL,
  `sync_binlog_position` varchar(255) NOT NULL,
  `sync_gtid_position` varchar(255) NOT NULL,
  `sync_state` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_integration_installations_on_integration_id_and_version` (`integration_id`,`integration_version_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;