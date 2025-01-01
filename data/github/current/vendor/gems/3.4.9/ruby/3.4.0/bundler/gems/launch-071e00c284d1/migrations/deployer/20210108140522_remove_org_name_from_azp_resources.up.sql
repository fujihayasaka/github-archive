ALTER TABLE azp_resources
	DROP KEY `by_organization_name`,
	DROP COLUMN `organization_name`,
	MODIFY COLUMN `tenant_name` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL;
