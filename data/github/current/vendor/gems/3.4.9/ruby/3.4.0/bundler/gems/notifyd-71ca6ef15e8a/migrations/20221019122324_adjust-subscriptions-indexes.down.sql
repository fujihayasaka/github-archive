ALTER TABLE `subscriptions_v2` DROP INDEX `idx_subscriptions_topic_user_trigger_meta_id`;
ALTER TABLE `subscriptions_v2` ADD CONSTRAINT `unique_subscriptions_topic_user_trigger_meta_id` UNIQUE (`shard_attribute`, `topic_type`,`topic_value`,`subject_type`,`trigger`,`meta_id`,`user_id`);
