INSERT INTO tg_contributions (created_at, repository_id, user_id, pushed_at, email)
SELECT created_at, repository_id, user_id, pushed_date, '' AS email
FROM ghas_repository_contributions
WHERE pushed_date >= DATE(NOW() - INTERVAL 100 DAY)
ON DUPLICATE KEY
UPDATE pushed_at = GREATEST(pushed_date, pushed_at)
