INSERT IGNORE INTO tg_users (created_at, updated_at, user_id, login, type)
SELECT created_at, updated_at, id, login, type
FROM users
WHERE (
    id IN (SELECT DISTINCT user_id FROM tg_contributions) OR
    id IN (SELECT DISTINCT owner_id FROM tg_repositories)
)
