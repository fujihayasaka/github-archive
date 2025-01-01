ALTER TABLE `routing_setting_channels` DROP INDEX `unique_routing_setting_channels_rs_id_with_channel`;
CREATE INDEX `index_channels_routing_setting_id` ON `routing_setting_channels` (`routing_setting_id`);

ALTER TABLE `routing_setting_custom_fields` DROP INDEX `idx_routing_setting_custom_fields_meta_id_name_value`;
