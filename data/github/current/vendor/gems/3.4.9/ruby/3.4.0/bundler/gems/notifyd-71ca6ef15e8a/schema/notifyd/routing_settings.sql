CREATE TABLE `routing_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `topic_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `topic_value` varchar(255) COLLATE utf8mb4_unicode_ci NOT NULL,
  `subject_type` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `trigger` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `reason` varchar(100) COLLATE utf8mb4_unicode_ci NOT NULL,
  `notify` tinyint(1) DEFAULT NULL,
  `meta_id` bigint NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_unique_routing_settings` (`topic_type`,`topic_value`,`subject_type`,`trigger`,`reason`,`meta_id`,`user_id`),
  KEY `index_routing_settings_user_id` (`user_id`),
  KEY `index_routing_settings_meta_id` (`meta_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
