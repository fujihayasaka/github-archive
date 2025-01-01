ALTER TABLE `workflow_build_executions`
DROP COLUMN `actor_id`,
DROP INDEX `by_actor_id_state_queued_at`;