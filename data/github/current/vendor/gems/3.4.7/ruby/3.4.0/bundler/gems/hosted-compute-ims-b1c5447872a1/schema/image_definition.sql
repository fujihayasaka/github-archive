CREATE TABLE `image_definition` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` varchar(128) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'github or github/github global_id of the owner of this image',
  `name` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_as_cs NOT NULL COMMENT 'Case sensitive name as assigned by github/owner of this image',
  `image_type` enum('Curated','Customer') COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether this image is available for use',
  `feature_flag` varchar(128) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL COMMENT 'Feature flag associated with the image',
  `os_type` enum('Linux','Windows','MacOS') COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `architecture` enum('X64','Arm64') COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `azure_subscription_id` bigint unsigned DEFAULT NULL COMMENT 'The PK (id) field of the azure_subscription table',
  `points_to_image_definition_id` bigint unsigned DEFAULT NULL COMMENT 'If populated the PK (id) field of the an existing image_definition record. Thereby identifying that record as the latest image definition.',
  `created_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `by_name_image_type` (`name`,`image_type`,`owner_id`) COMMENT 'Prevents duplicate names for Github-owned images but allows other image owners to use the same name as a Github owned image',
  KEY `by_image_type` (`image_type`),
  KEY `by_owner_id_image_type` (`owner_id`,`image_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;


