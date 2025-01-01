ALTER TABLE `ts_codeql_runs` ADD KEY `index_codeql_runs_on_repository_id_and_sha` (`repository_id`,`sha`);
