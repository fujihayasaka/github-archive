ALTER TABLE `ts_codeql_runs` ADD KEY `index_codeql_runs_on_run_type_and_status` (`run_type`,`status`);
