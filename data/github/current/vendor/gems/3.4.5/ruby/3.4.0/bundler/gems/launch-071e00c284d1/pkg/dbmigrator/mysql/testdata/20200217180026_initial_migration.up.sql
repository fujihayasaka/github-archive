CREATE TABLE `test_table` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `body` varchar(255) NOT NULL,

  PRIMARY KEY (`id`),
  KEY `by_body` (`body`)
) ENGINE=InnoDB CHARSET=utf8mb4 COLLATE=utf8mb4_bin;
