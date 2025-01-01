ALTER TABLE workflow_builds
MODIFY COLUMN `checkout_ref` varbinary(1024) NOT NULL;