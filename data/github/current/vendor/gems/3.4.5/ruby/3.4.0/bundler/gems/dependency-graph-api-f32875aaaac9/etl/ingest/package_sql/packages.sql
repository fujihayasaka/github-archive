INSERT INTO %packages_table_name%
  (
    package_manager,
    name,
    label,
    last_published_at,
    created_at,
    updated_at
  )
VALUES
  (
    :package_manager,
    :package_name,
    :package_label,
    :last_published_at,
    NOW(),
    NOW()
  )
ON DUPLICATE KEY UPDATE
  id = LAST_INSERT_ID(id),
  package_manager = VALUES(package_manager),
  name = VALUES(name),
  last_published_at = (
    CASE
    WHEN VALUES(last_published_at) IS NOT NULL
      THEN GREATEST(COALESCE(last_published_at, VALUES(last_published_at)), VALUES(last_published_at))
    ELSE last_published_at
    END),
  updated_at = VALUES(updated_at)
