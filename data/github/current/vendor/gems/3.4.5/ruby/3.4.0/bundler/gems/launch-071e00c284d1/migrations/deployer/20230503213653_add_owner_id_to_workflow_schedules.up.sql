ALTER TABLE `workflow_schedules`
ADD COLUMN `owner_id` bigint(20) unsigned COMMENT 'The id of the owner that owns the repository at the time of scheduled workflow creation';