ALTER TABLE workflow_build_executions
DROP INDEX `by_workflow_build_id_webhook_delivery_id`, 
ADD UNIQUE KEY `by_webhook_delivery_id` (`webhook_delivery_id`);
