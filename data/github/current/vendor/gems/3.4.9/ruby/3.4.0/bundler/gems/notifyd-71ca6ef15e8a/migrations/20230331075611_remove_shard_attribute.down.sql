ALTER TABLE routing_setting_channels ADD shard_attribute varchar(100) NOT NULL DEFAULT '';
ALTER TABLE routing_setting_match_rules ADD shard_attribute varchar(100) NOT NULL DEFAULT '';
ALTER TABLE routing_settings ADD shard_attribute varchar(100) NOT NULL DEFAULT '';
ALTER TABLE subscription_match_rules ADD shard_attribute varchar(100) NOT NULL DEFAULT '';
ALTER TABLE subscriptions_v2 ADD shard_attribute varchar(100) NOT NULL DEFAULT '';
