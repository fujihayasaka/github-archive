ALTER TABLE workflow_builds
DROP KEY `by_actor_id_state_queued_at`,
DROP COLUMN `actor_id`;
