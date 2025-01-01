
CREATE UNIQUE INDEX `unique_routing_setting_channels_rs_id_with_channel` ON `routing_setting_channels` (`routing_setting_id`,`channel`);
ALTER TABLE `routing_setting_channels` DROP INDEX `index_channels_routing_setting_id`;

CREATE INDEX `idx_routing_setting_custom_fields_meta_id_name_value` ON `routing_setting_custom_fields` (`meta_id`, `name`, `value`);