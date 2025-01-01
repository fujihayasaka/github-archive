DROP INDEX `unique_routing_settings` ON `routing_settings`;
ALTER TABLE `routing_settings` ADD CONSTRAINT `unique_routing_settings_topic_subject_trigger_user` UNIQUE (`shard_attribute`,`topic_type`,`topic_value`,`subject_type`,`trigger`, `meta_id`,`user_id`);
