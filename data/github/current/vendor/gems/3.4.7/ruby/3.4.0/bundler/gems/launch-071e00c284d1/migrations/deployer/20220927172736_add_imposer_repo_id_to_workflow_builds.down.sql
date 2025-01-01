ALTER TABLE `workflow_builds`
DROP COLUMN `imposer_repository_id`,
DROP KEY `by_delivery_id_workflow_file_path_event_imposer_repo_id`,
ADD UNIQUE KEY `by_delivery_id_workflow_file_path_event` (`webhook_delivery_id`, `workflow_file_path`, `event`);