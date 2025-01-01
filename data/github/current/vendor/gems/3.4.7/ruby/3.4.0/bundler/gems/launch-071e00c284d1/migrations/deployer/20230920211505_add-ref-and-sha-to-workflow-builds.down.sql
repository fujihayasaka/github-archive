ALTER TABLE `workflow_builds`
ADD UNIQUE KEY `by_delivery_id_workflow_file_path_event_imposer_repo_id` (`webhook_delivery_id`,`workflow_file_path`,`event`,`imposer_repository_id`),
DROP INDEX `by_delivery_id_workflow_file_path_event_imposer_sha_ref`, 
MODIFY `event` VARCHAR(255) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '' COMMENT 'The GitHub event that kicked off a build',
DROP COLUMN `workflow_sha`,
DROP COLUMN `pinned_workflow_ref`;