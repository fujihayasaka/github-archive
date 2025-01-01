DROP TABLE IF EXISTS `oauth_applications`;
CREATE TABLE `oauth_applications` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  `url` text,
  `callback_url` text,
  `key` varchar(20) DEFAULT NULL,
  `user_id` int(11) DEFAULT NULL,
  `created_at` datetime DEFAULT NULL,
  `updated_at` datetime DEFAULT NULL,
  `domain` varchar(100) DEFAULT NULL,
  `rate_limit` int(11) unsigned DEFAULT NULL,
  `full_trust` tinyint(1) unsigned DEFAULT '0',
  `description` text,
  `logo_id` int(11) DEFAULT NULL,
  `state` int(11) DEFAULT '0',
  `raw_data` blob,
  `temporary_rate_limit` mediumint(9) DEFAULT NULL,
  `temporary_rate_limit_expires_at` datetime DEFAULT NULL,
  `bgcolor` varchar(6) NOT NULL DEFAULT 'ffffff',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_oauth_applications_on_key` (`key`),
  KEY `index_oauth_applications_on_user_id_and_name` (`user_id`,`name`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8;