ALTER TABLE `workflow_builds`
ADD INDEX `by_repository_id` (`repository_id`),
ADD INDEX `by_executing_actor_id_state_queued_at` (`executing_actor_id`,`state`,`queued_at`),
ADD INDEX `by_queued_at` (`queued_at`),
ADD INDEX `by_completed_at_created_at` (`completed_at`,`created_at`),
ADD INDEX `by_external_build_id` (`external_build_id`),
ADD INDEX `by_workflow_id_event_repository_id` (`workflow_id`,`event`,`repository_id`),
ADD INDEX `by_workflow_id_event_repository_next_id` (`workflow_id`,`event`,`repository_next_id`);
