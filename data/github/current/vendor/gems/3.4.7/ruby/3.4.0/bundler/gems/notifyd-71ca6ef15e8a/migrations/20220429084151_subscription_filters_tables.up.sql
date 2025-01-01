CREATE TABLE IF NOT EXISTS `routing_settings` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `shard_attribute` varchar(100) NOT NULL,
  `topic_type` varchar(100) NOT NULL,
  `topic_value` varchar(255) NOT NULL,
  `subject_type` varchar(100) NOT NULL,
  `trigger` varchar(100) NOT NULL,
  `reason` varchar(100) NOT NULL,
  `notify` boolean,
  `meta_id` bigint(20) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_routing_settings_topic_subject_trigger_user` (`shard_attribute`, `topic_type`, `topic_value`, `subject_type`, `trigger`, `meta_id`, `user_id`),
  KEY `index_routing_settings_user_id` (`user_id`),
  KEY `index_routing_settings_meta_id` (`meta_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS`routing_setting_match_rules` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shard_attribute` varchar(100) NOT NULL,
  `routing_setting_id` bigint(20) unsigned NOT NULL,
  `attribute` varchar(100) NOT NULL,
  `value` varchar(255) NOT NULL,
  `match` varchar(20) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_routing_setting_match_rules` (`shard_attribute`, `attribute`, `value`, `routing_setting_id`),
  KEY `index_routing_setting_match_rules` (`shard_attribute`, `routing_setting_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `meta_routing_settings` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `details` JSON DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_meta_routing_settings_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
