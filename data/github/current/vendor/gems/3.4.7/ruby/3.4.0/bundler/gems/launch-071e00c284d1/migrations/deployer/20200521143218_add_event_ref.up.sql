ALTER TABLE workflow_builds
ADD COLUMN `event_ref` varbinary(1024) NOT NULL DEFAULT '';
