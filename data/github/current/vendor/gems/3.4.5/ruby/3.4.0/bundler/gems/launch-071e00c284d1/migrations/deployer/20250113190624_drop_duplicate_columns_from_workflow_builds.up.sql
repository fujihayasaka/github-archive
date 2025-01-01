ALTER TABLE `workflow_builds`
  DROP COLUMN `started_at`,
  DROP COLUMN `external_build_id`,
  DROP COLUMN `was_delayed`;
