CREATE TABLE `subscriptions_v2` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `topic_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `topic_value` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `trigger` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `reason` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `meta_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `index_subscriptions_user_id` (`user_id`),
  KEY `index_subscriptions_meta_id` (`meta_id`),
  KEY `idx_subscriptions_topic_user_trigger_meta_id` (`topic_type`,`topic_value`,`subject_type`,`trigger`,`meta_id`,`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
