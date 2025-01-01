ALTER TABLE `workflow_jobs`
DROP COLUMN `check_run_next_id`,
DROP INDEX `by_check_run_next_id`;