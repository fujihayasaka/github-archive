-- Tracks a vestigial table on the authnd-production cluster.  Not used for dev/test/CI.
CREATE TABLE `organization_credential_authorizations` (
  `id` int(11) NOT NULL,
  `organization_id` int(11) NOT NULL,
  `credential_id` int(11) NOT NULL,
  `credential_type` varchar(30) NOT NULL,
  `created_at` datetime NOT NULL,
  `revoked_at` datetime DEFAULT NULL,
  `revoked_by_id` int(11) DEFAULT NULL,
  `sync_timestamp` datetime NOT NULL,
  `sync_kafka_offset` bigint(20) NOT NULL,
  `sync_binlog_position` varchar(255) NOT NULL,
  `sync_gtid_position` varchar(255) NOT NULL,
  `sync_state` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_on_credential_id_and_credential_type` (`credential_id`,`credential_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
