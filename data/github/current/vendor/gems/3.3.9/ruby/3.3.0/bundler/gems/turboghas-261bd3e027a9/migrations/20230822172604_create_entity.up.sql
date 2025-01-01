INSERT IGNORE INTO tg_entities (created_at, updated_at, entity_type, entity_id, user_ids)
VALUES (NOW(), NOW(), 'Business', 1, CAST('null' AS JSON))
