ALTER TABLE `ts_codeql_runs` DROP KEY `index_codeql_runs_on_repository_id`, ADD KEY `index_codeql_runs_on_repository_id_event_created_at` (`repository_id`,`triggering_event`,`created_at`);
