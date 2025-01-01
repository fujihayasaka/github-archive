ALTER TABLE workflow_builds
	MODIFY COLUMN `token_permissions` json DEFAULT NULL COMMENT 'The serialized token.PermissionSettings for run';
