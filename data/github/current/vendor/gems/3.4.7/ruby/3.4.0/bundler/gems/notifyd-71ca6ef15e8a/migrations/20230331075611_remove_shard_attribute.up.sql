ALTER TABLE routing_setting_channels DROP COLUMN shard_attribute;
ALTER TABLE routing_setting_match_rules DROP COLUMN shard_attribute;
ALTER TABLE routing_settings DROP COLUMN shard_attribute;
ALTER TABLE subscription_match_rules DROP COLUMN shard_attribute;
ALTER TABLE subscriptions_v2 DROP COLUMN shard_attribute;