CREATE TABLE `oauth_authorizations` (
	  `id` int(11) NOT NULL AUTO_INCREMENT,
	  `user_id` int(11) NOT NULL,
	  `application_id` int(11) NOT NULL,
	  `accessed_at` datetime DEFAULT NULL,
	  `created_at` datetime NOT NULL,
	  `updated_at` datetime NOT NULL,
	  `description` varchar(255) DEFAULT NULL,
	  `scopes` text,
	  `application_type` varchar(16) DEFAULT NULL,
	  `integration_version_number` int(11) DEFAULT NULL,
	  PRIMARY KEY (`id`),
	  KEY `index_oauth_authorizations_on_accessed_at_and_created_at` (`accessed_at`,`created_at`),
	  KEY `index_oauth_authorizations_on_user_id_and_appl_id_and_appl_type` (`user_id`,`application_id`,`application_type`),
	  KEY `index_oauth_authorizations_on_application_id_and_created_at` (`application_id`,`created_at`),
	  KEY `index_authorizations_on_application_id_type_version_number` (`application_id`,`application_type`,`integration_version_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;