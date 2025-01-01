ALTER TABLE `workflow_builds`
DROP COLUMN `executing_actor_id`,
DROP INDEX `by_executing_actor_id_state_queued_at`;