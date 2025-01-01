ALTER TABLE `workflow_build_executions`
DROP COLUMN `triggering_actor_next_id`,
DROP INDEX `by_triggering_actor_next_id_state_queued_at`;