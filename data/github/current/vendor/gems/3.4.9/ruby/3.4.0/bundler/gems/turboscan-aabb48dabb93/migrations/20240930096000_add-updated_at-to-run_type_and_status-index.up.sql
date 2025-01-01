ALTER TABLE `ts_codeql_runs` DROP KEY `index_codeql_runs_on_run_type_and_status`, ADD KEY `index_codeql_runs_on_run_type_status_and_updated_at` (`run_type`,`status`,`updated_at`);
