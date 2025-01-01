ALTER TABLE workflow_build_executions
DROP INDEX `by_webhook_delivery_id`, 
ADD UNIQUE KEY `by_workflow_build_id_webhook_delivery_id` (`workflow_build_id`,`webhook_delivery_id`);