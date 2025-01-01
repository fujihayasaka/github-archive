ALTER TABLE `payloads`
  ADD COLUMN `workflow_build_id` bigint(20) unsigned DEFAULT NULL,
  ADD INDEX `by_workflow_build_id` (`workflow_build_id`);
