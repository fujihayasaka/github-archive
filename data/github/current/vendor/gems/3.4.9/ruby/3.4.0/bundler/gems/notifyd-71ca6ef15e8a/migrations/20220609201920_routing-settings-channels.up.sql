CREATE TABLE IF NOT EXISTS `routing_setting_channels` (
    `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
    `shard_attribute` varchar(100) NOT NULL,
    `routing_setting_id` bigint(20) NOT NULL,
    `channel` varchar(20) NOT NULL,
    `enabled` boolean,
    `created_at` datetime NOT NULL,
    `updated_at` datetime NOT NULL,
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_channel_routing_setting_id_channel` (`shard_attribute`, `routing_setting_id`, `channel`),
    KEY `index_channels_routing_setting_id` (`routing_setting_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
