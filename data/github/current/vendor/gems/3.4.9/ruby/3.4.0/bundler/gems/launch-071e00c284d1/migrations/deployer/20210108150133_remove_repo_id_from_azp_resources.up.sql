ALTER TABLE azp_resources
	DROP COLUMN `repository_id`,
	MODIFY COLUMN `entity_id` varchar(120) COLLATE utf8mb4_bin NOT NULL COMMENT 'stores a global_relay_id that can relate to any github type - see azp_resources.go';
