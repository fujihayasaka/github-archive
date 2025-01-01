ALTER TABLE `ts_branch_protection_rules` DROP KEY `index_on_repository_id_rule_eid`, ADD UNIQUE KEY `index_on_repository_id_rule_eid` (`repository_id`,`rule_eid`);
