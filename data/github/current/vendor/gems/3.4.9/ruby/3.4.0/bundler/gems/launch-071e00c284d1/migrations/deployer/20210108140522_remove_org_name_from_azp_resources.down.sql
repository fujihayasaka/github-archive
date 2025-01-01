ALTER TABLE azp_resources
	ADD COLUMN `organization_name` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL,
	ADD KEY `by_organization_name` (`organization_name`),
	MODIFY COLUMN `tenant_name` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'to replace organization_name';
