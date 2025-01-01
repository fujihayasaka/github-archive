ALTER TABLE `ts_codeql_configs` ADD KEY `index_codeql_configs_for_refresh` (`onboarding_status`, `updated_at`, `repository_id`);
