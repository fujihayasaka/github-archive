
ALTER TABLE `subscription_match_rules` DROP INDEX `unique_subscription_match_rules`;
ALTER TABLE `subscription_match_rules` DROP INDEX `index_subscription_match_rules`;

ALTER TABLE `subscription_match_rules` ADD UNIQUE INDEX `unique_subscription_match_rules` (`attribute`,`value`,`subscription_id`);
ALTER TABLE `subscription_match_rules` ADD INDEX `index_subscription_match_rules` (`subscription_id`);
