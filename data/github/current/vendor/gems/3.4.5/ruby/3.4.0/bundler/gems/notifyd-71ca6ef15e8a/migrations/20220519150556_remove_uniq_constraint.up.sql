ALTER TABLE `meta_routing_settings` DROP INDEX `index_meta_routing_settings_user_id`;
ALTER TABLE `meta_routing_settings` ADD INDEX `idx_meta_routing_settings_user_id` (`user_id`);