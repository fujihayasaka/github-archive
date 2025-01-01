CREATE TABLE `image_version` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `version` varchar(32) COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Version of the image',
  `image_definition_id` bigint unsigned NOT NULL COMMENT 'The PK (id) field of the image_definition table',
  `state` enum('Pending','Provisioning','Ready','ProvisionFailed','Deleting') COLLATE utf8mb4_unicode_520_ci NOT NULL COMMENT 'Image version state',
  `state_details` varchar(1024) COLLATE utf8mb4_unicode_520_ci DEFAULT '' COMMENT 'Details of the image version state',
  `enabled` tinyint(1) NOT NULL DEFAULT '1' COMMENT 'Indicates whether this image version is available for use',
  `size_gb` bigint DEFAULT NULL COMMENT 'Size of the image version',
  `resource_id` varchar(1024) NOT NULL COLLATE utf8mb4_unicode_520_ci DEFAULT '' COMMENT 'Pointer to image resource in Azure',
  `created_at` datetime(6) DEFAULT CURRENT_TIMESTAMP(6),
  `updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `by_version_image_definition_id` (`version`,`image_definition_id`),
  KEY `by_image_definition_id` (`image_definition_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;
