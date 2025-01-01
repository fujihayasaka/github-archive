ALTER TABLE `workflow_builds`
ADD COLUMN `delivery_id` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL DEFAULT '';
