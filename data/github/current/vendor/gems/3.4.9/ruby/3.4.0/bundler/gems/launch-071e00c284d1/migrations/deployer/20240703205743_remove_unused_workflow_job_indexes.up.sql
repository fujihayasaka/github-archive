ALTER TABLE `workflow_jobs`
DROP INDEX `by_workflow_build_id`,
DROP INDEX `by_check_run_id`,
DROP INDEX `by_workflow_build_execution_id`,
DROP INDEX `by_check_run_next_id`;