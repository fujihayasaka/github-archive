CREATE TABLE IF NOT EXISTS `payloads` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `body` MEDIUMBLOB DEFAULT NULL COMMENT 'The body of the persisted payload',
  `compression_type` int(9) NOT NULL DEFAULT '0' COMMENT 'See CompressionType for values',
  PRIMARY KEY (`id`),
  KEY `by_created_at` (`created_at`)
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
