CREATE TABLE `payloads` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `body` mediumblob COMMENT 'The body of the persisted payload',
  `compression_type` int NOT NULL DEFAULT '0' COMMENT 'See CompressionType for values',
  `workflow_build_id` bigint unsigned DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `by_created_at` (`created_at`),
  KEY `by_workflow_build_id` (`workflow_build_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
