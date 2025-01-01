ALTER TABLE azp_resources
	ADD UNIQUE KEY `repository_id` (`repository_id`,`environment`);
