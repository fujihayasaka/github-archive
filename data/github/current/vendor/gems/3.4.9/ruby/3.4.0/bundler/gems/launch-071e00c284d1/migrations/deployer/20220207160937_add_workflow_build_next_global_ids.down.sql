ALTER TABLE `workflow_builds`
DROP COLUMN `check_suite_next_id`,
DROP COLUMN `repository_next_id`,
DROP COLUMN `executing_actor_next_id`,
DROP INDEX `by_check_suite_next_id`,
DROP INDEX `by_repository_next_id`,
DROP INDEX `by_workflow_id_event_repository_next_id`,
DROP INDEX `by_executing_actor_next_id_state_queued_at`;