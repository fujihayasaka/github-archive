ALTER TABLE workflow_build_executions
    DROP KEY `by_webhook_delivery_id`,
    DROP COLUMN `reporting_metadata`,
    DROP COLUMN `token_permissions`,
    DROP COLUMN `webhook_delivery_id`;