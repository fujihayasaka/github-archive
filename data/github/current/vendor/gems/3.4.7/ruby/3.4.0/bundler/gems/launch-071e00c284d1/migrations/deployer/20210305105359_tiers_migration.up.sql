ALTER TABLE workflow_schedules
ADD COLUMN `tier` tinyint(2) NOT NULL DEFAULT '3',
ADD COLUMN `tier_updated_at` datetime(6) DEFAULT NULL;
