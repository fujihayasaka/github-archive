CREATE TABLE `azure_subscription` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `subscription_id` varchar(36) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs NOT NULL COMMENT 'Azure subscription ID',
  `image_type` enum('Curated','Customer','Mixed') COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `image_count` int unsigned NOT NULL DEFAULT '0' COMMENT 'Number of images stored in this azure subscription',
  `created_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` datetime(6) DEFAULT NULL,
  `resources_prefix` varchar(30) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Unique resource prefix for Azure resources',
  PRIMARY KEY (`id`),
  UNIQUE KEY `by_subscription_id` (`subscription_id`),
  KEY `by_image_type` (`image_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;