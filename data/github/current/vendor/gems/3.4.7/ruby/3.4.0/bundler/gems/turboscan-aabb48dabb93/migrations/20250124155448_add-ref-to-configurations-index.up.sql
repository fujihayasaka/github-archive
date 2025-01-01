ALTER TABLE `ts_configurations` DROP KEY `index_configurations_on_repository_id`, ADD KEY `index_configurations_on_repository_id_and_ref` (`repository_id`,`ref`);
