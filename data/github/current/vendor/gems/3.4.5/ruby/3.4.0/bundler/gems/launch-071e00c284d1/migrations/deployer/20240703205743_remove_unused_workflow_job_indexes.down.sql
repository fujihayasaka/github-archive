ALTER TABLE `workflow_jobs`
ADD INDEX `by_workflow_build_id` (`workflow_build_id`),
ADD INDEX `by_check_run_id` (`check_run_id`),
ADD INDEX `by_workflow_build_execution_id` (`workflow_build_execution_id`),
ADD INDEX `by_check_run_next_id` (`check_run_next_id`);