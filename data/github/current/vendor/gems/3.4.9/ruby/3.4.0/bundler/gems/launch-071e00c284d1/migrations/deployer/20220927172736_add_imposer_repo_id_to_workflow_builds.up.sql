ALTER TABLE `workflow_builds`
ADD COLUMN `imposer_repository_id` bigint(20) unsigned DEFAULT '0' COMMENT 'The source repository of a required workflow. This will be 0 for non required workflows',
ADD UNIQUE KEY `by_delivery_id_workflow_file_path_event_imposer_repo_id` (`webhook_delivery_id`, `workflow_file_path`, `event`, `imposer_repository_id`),
DROP KEY `by_delivery_id_workflow_file_path_event`;