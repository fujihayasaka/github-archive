ALTER TABLE `workflow_builds`
DROP INDEX `by_repository_id`,
DROP INDEX `by_executing_actor_id_state_queued_at`,
DROP INDEX `by_queued_at`,
DROP INDEX `by_completed_at_created_at`,
DROP INDEX `by_external_build_id`,
DROP INDEX `by_workflow_id_event_repository_id`,
DROP INDEX `by_workflow_id_event_repository_next_id`;
