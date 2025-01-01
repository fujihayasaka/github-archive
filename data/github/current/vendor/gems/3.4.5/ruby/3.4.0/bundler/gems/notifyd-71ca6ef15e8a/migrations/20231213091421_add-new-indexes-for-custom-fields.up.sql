ALTER TABLE `subscription_custom_fields` ADD UNIQUE INDEX `unique_subscription_custom_fields_name_value_meta_id` (`name`,`value`,`meta_id`);
ALTER TABLE `routing_setting_custom_fields` ADD UNIQUE INDEX `unique_routing_setting_custom_fields_name_value_meta_id` (`name`,`value`,`meta_id`);
