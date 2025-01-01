ALTER TABLE azp_resources
	MODIFY COLUMN `entity_id` varchar(120) COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'to replace repository_id',
	ADD COLUMN `repository_id` varchar(120) COLLATE utf8mb4_bin NOT NULL COMMENT 'stores a global_relay_id that can relate to any github type - see azp_resources.go';
