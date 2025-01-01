DROP TABLE IF EXISTS `integration_installations`;
CREATE TABLE `integration_installations` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `integration_id` int(11) NOT NULL,
  `target_id` bigint unsigned NOT NULL,
  `target_type` varchar(30) NOT NULL,
  `user_suspended_by_id` int(11) DEFAULT NULL,
  `integrator_suspended` tinyint(1) NOT NULL DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `index_integration_installations_on_user_suspended_by_id` (`user_suspended_by_id`),
  KEY `index_integration_installations_on_integrator_suspended` (`integrator_suspended`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;