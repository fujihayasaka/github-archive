ALTER TABLE `workflow_builds`
ADD COLUMN `workflow_sha` VARCHAR(40) NOT NULL DEFAULT '' COMMENT 'The sha of the workflow file',
ADD COLUMN `pinned_workflow_ref` VARBINARY(1024) NOT NULL DEFAULT '' COMMENT 'The ref of the required workflow file if it is pinned to a ref',
MODIFY `event` VARCHAR(40) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '' COMMENT 'The GitHub event that kicked off a build',
DROP INDEX `by_delivery_id_workflow_file_path_event_imposer_repo_id`,
ADD UNIQUE KEY `by_delivery_id_workflow_file_path_event_imposer_sha_ref` (`webhook_delivery_id`,`workflow_file_path`,`event`,`imposer_repository_id`,`workflow_sha`,`pinned_workflow_ref`);