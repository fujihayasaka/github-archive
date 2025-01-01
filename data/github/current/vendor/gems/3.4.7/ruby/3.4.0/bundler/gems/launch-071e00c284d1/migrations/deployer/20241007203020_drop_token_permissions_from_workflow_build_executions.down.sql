ALTER TABLE `workflow_build_executions`
ADD COLUMN `token_permissions` json DEFAULT NULL COMMENT 'See InstallationPermissions for values';
