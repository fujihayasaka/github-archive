ALTER TABLE workflow_build_executions
    ADD COLUMN `webhook_delivery_id` VARCHAR(50) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
    ADD COLUMN `reporting_metadata` JSON DEFAULT NULL COMMENT 'See WorkflowMetadata for values',
    ADD COLUMN `token_permissions` JSON DEFAULT NULL COMMENT 'See InstallationPermissions for values',
    ADD UNIQUE KEY `by_webhook_delivery_id` (`webhook_delivery_id`);