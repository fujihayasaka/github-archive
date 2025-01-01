
ALTER TABLE `subscription_match_rules` DROP INDEX `unique_subscription_match_rules`;
ALTER TABLE `subscription_match_rules` DROP INDEX `index_subscription_match_rules`;

CREATE UNIQUE INDEX `unique_subscription_match_rules` ON `subscription_match_rules` (`shard_attribute`, `attribute`,`value`,`subscription_id`),
CREATE INDEX `index_subscription_match_rules` ON `subscription_match_rules` (`shard_attribute`, `subscription_id`),
