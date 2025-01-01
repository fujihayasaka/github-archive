ALTER TABLE `ts_analysis_rules` DROP KEY `index_repo_analysis_rule`, ADD KEY `idx_analysis_rules_repo_analysis` (`repository_id`,`analysis_id`);
