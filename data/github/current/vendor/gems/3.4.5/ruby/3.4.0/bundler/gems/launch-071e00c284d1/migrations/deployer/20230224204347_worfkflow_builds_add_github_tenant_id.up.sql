ALTER TABLE `workflow_builds`
ADD COLUMN `github_tenant_id` bigint(20) unsigned COMMENT 'The github tenant id (business id) owning that repository that triggered the workflow. This value will always be NULL in non multi-tenant environments';
