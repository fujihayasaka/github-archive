CREATE TABLE `businesses` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `slug` varchar(60) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `shortcode` varchar(32) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `spammy` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_businesses_on_slug` (`slug`),
  UNIQUE KEY `index_businesses_on_shortcode` (`shortcode`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
