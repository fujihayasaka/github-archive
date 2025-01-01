-- Tracks a vestigial table on the authnd-production cluster.  Not used for dev/test/CI.
CREATE TABLE `public_keys` (
  `id` int(11) NOT NULL,
  `key` text NOT NULL,
  `fingerprint` varbinary(64) NOT NULL,
  `title` varchar(255) NOT NULL,
  `read_only` tinyint(1) NOT NULL,
  `actor_id` int(11) NOT NULL,
  `actor_type` tinyint(1) NOT NULL,
  `verified_at` datetime DEFAULT NULL,
  `sync_timestamp` datetime NOT NULL,
  `sync_kafka_offset` bigint(20) NOT NULL,
  `sync_binlog_position` varchar(255) NOT NULL,
  `sync_gtid_position` varchar(255) NOT NULL,
  `sync_state` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_public_keys_on_fingerprint` (`fingerprint`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;