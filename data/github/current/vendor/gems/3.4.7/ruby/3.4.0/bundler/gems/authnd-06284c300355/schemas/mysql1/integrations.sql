CREATE TABLE `integrations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `owner_id` bigint unsigned NOT NULL,
  `owner_type` varchar(32) NOT NULL DEFAULT 'User',
  `bot_id` bigint unsigned NOT NULL,
  `name` varchar(255) NOT NULL,
  `created_at` datetime NOT NULL,
  `key` varchar(20) DEFAULT NULL,
  `state` int NOT NULL DEFAULT '0',
  `user_hidden` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_integrations_on_key` (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;