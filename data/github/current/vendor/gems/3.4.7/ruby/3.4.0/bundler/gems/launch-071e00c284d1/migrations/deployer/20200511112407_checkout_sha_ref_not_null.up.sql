ALTER TABLE workflow_builds
MODIFY COLUMN `checkout_sha` varchar(40) NOT NULL,
MODIFY COLUMN `checkout_ref` varchar(40) NOT NULL;
