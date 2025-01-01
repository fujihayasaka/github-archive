ALTER TABLE workflow_builds
	MODIFY COLUMN `token_permissions` json DEFAULT NULL COMMENT 'See InstallationPermissions for values';
