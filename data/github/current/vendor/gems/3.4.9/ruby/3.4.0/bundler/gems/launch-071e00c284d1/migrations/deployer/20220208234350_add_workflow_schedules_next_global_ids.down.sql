ALTER TABLE `workflow_schedules`
DROP COLUMN `schedule_next_hash`,
DROP COLUMN `repository_next_id`,
DROP COLUMN `actor_next_id`,
DROP KEY `by_schedule_next_hash`,
DROP KEY `by_repository_next_id`;