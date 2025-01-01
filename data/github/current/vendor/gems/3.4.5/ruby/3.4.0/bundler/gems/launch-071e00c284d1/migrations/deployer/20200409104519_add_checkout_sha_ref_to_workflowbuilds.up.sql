ALTER TABLE workflow_builds
ADD COLUMN `checkout_sha` varchar(40),
ADD COLUMN `checkout_ref` varchar(40);
