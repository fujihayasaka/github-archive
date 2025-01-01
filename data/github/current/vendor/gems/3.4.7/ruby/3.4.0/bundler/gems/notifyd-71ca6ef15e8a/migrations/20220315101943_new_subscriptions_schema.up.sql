CREATE TABLE IF NOT EXISTS `subscriptions_v2` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `shard_attribute` varchar(100) NOT NULL,
  `topic_type` varchar(100) NOT NULL,
  `topic_value` varchar(255) NOT NULL,
  `subject_type` varchar(100) NOT NULL,
  `trigger` varchar(100) NOT NULL,
  `reason` varchar(100) NOT NULL,
  `meta_id`  bigint(20) unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_subscriptions_topic_user_trigger_meta_id` (`shard_attribute`, `topic_type`, `topic_value`, `subject_type`, `trigger`, `meta_id`, `user_id`),
  KEY `index_subscriptions_user_id` (`user_id`),
  KEY `index_subscriptions_meta_id` (`meta_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS`subscription_match_rules` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `shard_attribute` varchar(100) NOT NULL,
  `subscription_id` bigint(20) unsigned NOT NULL,
  `attribute` varchar(100) NOT NULL,
  `value` varchar(255) NOT NULL,
  `match` varchar(20) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_subscription_match_rules` (`shard_attribute`, `attribute`, `value`, `subscription_id`),
  KEY `index_subscription_match_rules` (`shard_attribute`, `subscription_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


CREATE TABLE IF NOT EXISTS `meta_subscriptions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `details` TEXT DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_meta_subscriptions_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `subscription_custom_fields` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint(20) unsigned NOT NULL,
  `meta_id`  bigint(20) unsigned NOT NULL,
  `name` varchar(100) NOT NULL,
  `value` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_subscription_custom_fields_user_id_meta_id_name_value` (`user_id`, `meta_id`, `name`, `value`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
