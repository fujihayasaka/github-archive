ALTER TABLE `ts_codeql_runs` ADD UNIQUE KEY `index_codeql_runs_on_workflow_run_id` (`workflow_run_id`);
