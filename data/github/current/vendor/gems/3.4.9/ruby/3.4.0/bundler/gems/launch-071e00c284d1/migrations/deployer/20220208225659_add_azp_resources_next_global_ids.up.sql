ALTER TABLE `azp_resources`
ADD COLUMN `entity_next_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL AFTER `entity_id`,
ADD UNIQUE KEY `by_entity_next_id_environment` (`entity_next_id`, `environment`);