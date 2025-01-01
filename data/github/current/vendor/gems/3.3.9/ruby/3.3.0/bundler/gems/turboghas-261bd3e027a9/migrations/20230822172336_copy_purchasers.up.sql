INSERT IGNORE INTO tg_purchasers (created_at, updated_at, owner_id, entity_id, entity_type)
SELECT created_at, updated_at, id, 1, 'Business'
FROM users
WHERE id IN (SELECT DISTINCT owner_id FROM tg_repositories)
