ALTER TABLE workflow_jobs
ADD COLUMN `workflow_build_execution_id` bigint(20) unsigned DEFAULT NULL,
ADD INDEX `by_workflow_build_execution_id` (`workflow_build_execution_id`);
