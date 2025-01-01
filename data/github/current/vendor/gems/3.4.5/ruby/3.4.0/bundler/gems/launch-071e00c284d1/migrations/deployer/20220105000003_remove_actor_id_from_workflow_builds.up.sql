ALTER TABLE `workflow_builds`
DROP COLUMN `actor_id`,
DROP INDEX `by_actor_id_state_queued_at`;