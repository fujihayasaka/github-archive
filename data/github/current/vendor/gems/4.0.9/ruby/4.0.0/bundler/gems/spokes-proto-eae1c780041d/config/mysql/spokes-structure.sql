DROP TABLE IF EXISTS `cache_storage_policies`;
CREATE TABLE `cache_storage_policies` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `entity_id` bigint(20) unsigned NOT NULL,
  `entity_type` tinyint(4) NOT NULL,
  `cache_location` varchar(20) NOT NULL,
  `number_of_replicas` tinyint(4) NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_cache_storage_policies_on_entity_id_and_entity_type` (`entity_id`,`entity_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `cold_networks`;
CREATE TABLE `cold_networks` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `network_id` int(11) NOT NULL,
  `state` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_cold_networks_on_network_id` (`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `datacenters`;
CREATE TABLE `datacenters` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `datacenter` varchar(8) NOT NULL,
  `region` varchar(8) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_datacenters_on_datacenter` (`datacenter`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `fileservers`;
CREATE TABLE `fileservers` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `host` varchar(255) NOT NULL,
  `fqdn` varchar(255) NOT NULL,
  `embargoed` tinyint(1) NOT NULL DEFAULT '0',
  `online` tinyint(1) NOT NULL DEFAULT '0',
  `evacuating` tinyint(1) NOT NULL DEFAULT '0',
  `quiescing` tinyint(1) NOT NULL DEFAULT '0',
  `datacenter` varchar(20) DEFAULT NULL,
  `rack` varchar(20) DEFAULT NULL,
  `ip` varchar(45) DEFAULT NULL,
  `evacuating_reason` varchar(255) DEFAULT NULL,
  `quiescing_reason` varchar(255) DEFAULT NULL,
  `embargoed_reason` varchar(255) DEFAULT NULL,
  `non_voting` tinyint(1) NOT NULL DEFAULT '0',
  `hdd_storage` tinyint(1) NOT NULL DEFAULT '0',
  `site` varchar(20) DEFAULT NULL,
  `cache_location` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_fileservers_on_host` (`host`),
  UNIQUE KEY `index_fileservers_on_fqdn` (`fqdn`),
  KEY `index_fileservers_by_location` (`datacenter`,`rack`),
  KEY `index_fileservers_on_site_and_rack` (`site`,`rack`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `gist_replicas`;
CREATE TABLE `gist_replicas` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `gist_id` int(11) NOT NULL,
  `host` varchar(255) NOT NULL,
  `checksum` varchar(255) NOT NULL,
  `state` int(11) NOT NULL,
  `read_weight` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_gist_replicas_on_gist_id_and_host` (`gist_id`,`host`),
  KEY `index_gist_replicas_on_updated_at` (`updated_at`),
  KEY `index_gist_replicas_on_state` (`state`),
  KEY `index_gist_replicas_on_host_and_state_and_gist_id` (`host`,`state`,`gist_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `git_sizer`;
CREATE TABLE `git_sizer` (
  `id` int(11) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `repository_type` int(11) unsigned NOT NULL,
  `repository_id` int(11) unsigned NOT NULL,
  `max_blob_size_bytes` bigint(20) unsigned NOT NULL,
  `max_checkout_blob_count` bigint(20) unsigned NOT NULL,
  `max_checkout_blob_size_bytes` bigint(20) unsigned NOT NULL,
  `max_checkout_link_count` bigint(20) unsigned NOT NULL,
  `max_checkout_path_depth` bigint(20) unsigned NOT NULL,
  `max_checkout_path_length` bigint(20) unsigned NOT NULL,
  `max_checkout_submodule_count` bigint(20) unsigned NOT NULL,
  `max_checkout_tree_count` bigint(20) unsigned NOT NULL,
  `max_commit_parent_count` bigint(20) unsigned NOT NULL,
  `max_commit_size_bytes` bigint(20) unsigned NOT NULL,
  `max_history_depth` bigint(20) unsigned NOT NULL,
  `max_tag_depth` bigint(20) unsigned NOT NULL,
  `max_tree_entries` bigint(20) unsigned NOT NULL,
  `reference_count` bigint(20) unsigned NOT NULL,
  `unique_blob_count` bigint(20) unsigned NOT NULL,
  `unique_blob_size_bytes` bigint(20) unsigned NOT NULL,
  `unique_commit_count` bigint(20) unsigned NOT NULL,
  `unique_commit_size_bytes` bigint(20) unsigned NOT NULL,
  `unique_tag_count` bigint(20) unsigned NOT NULL,
  `unique_tree_count` bigint(20) unsigned NOT NULL,
  `unique_tree_entries` bigint(20) unsigned NOT NULL,
  `unique_tree_size_bytes` bigint(20) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_git_sizer_on_type_and_id` (`repository_id`,`repository_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `network_replicas`;
CREATE TABLE `network_replicas` (
  `id` bigint(11) unsigned NOT NULL AUTO_INCREMENT,
  `network_id` int(11) NOT NULL,
  `host` varchar(255) NOT NULL,
  `state` int(11) NOT NULL,
  `read_weight` int(11) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_on_host` (`network_id`,`host`),
  KEY `index_network_replicas_on_state` (`state`),
  KEY `index_network_replicas_on_host_and_state_and_network_id` (`host`,`state`,`network_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `repository_checksums`;
CREATE TABLE `repository_checksums` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `repository_id` int(11) NOT NULL,
  `repository_type` int(11) NOT NULL DEFAULT '0',
  `checksum` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repository_checksums_on_repository_type` (`repository_id`,`repository_type`),
  KEY `index_repository_checksums_on_updated_at` (`updated_at`),
  KEY `index_repository_checksums_on_repository_type_and_updated_at` (`repository_type`,`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `repository_replicas`;
CREATE TABLE `repository_replicas` (
  `id` bigint(11) unsigned NOT NULL AUTO_INCREMENT,
  `repository_id` int(11) NOT NULL,
  `repository_type` int(11) NOT NULL DEFAULT '0',
  `host` varchar(255) NOT NULL,
  `checksum` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `network_replica_id` bigint(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_repository_replicas_on_repository_type_and_host` (`repository_id`,`repository_type`,`host`),
  KEY `update_time` (`updated_at`),
  KEY `host_only` (`host`),
  KEY `index_repository_replicas_on_network_replica_id` (`network_replica_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
DROP TABLE IF EXISTS `sites`;
CREATE TABLE `sites` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `site` varchar(12) NOT NULL,
  `region` varchar(8) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_sites_on_site` (`site`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;