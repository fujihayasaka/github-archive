INSERT IGNORE INTO tg_repositories (created_at, updated_at, owner_id, repository_id, name, enabled)
SELECT
    repositories.created_at,
    repositories.updated_at,
    repositories.owner_id,
    repositories.id,
    repositories.name,
    EXISTS(
        SELECT 1
        FROM configuration_entries
        WHERE configuration_entries.target_id = repositories.id
          AND configuration_entries.target_type = 'Repository'
          AND configuration_entries.name = 'advanced_security.user_enabled'
    ) AS 'enabled'
FROM repositories
WHERE repositories.id IN (SELECT DISTINCT repository_id FROM tg_contributions)
  AND deleted_at IS NULL
