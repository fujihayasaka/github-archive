INSERT INTO %manifests_table_name%
  (
    package_manager,
    manifest_type,
    filename,
    path,
    name,
    latest_git_ref,
    last_pushed_at,
    repository_id,
    created_at,
    updated_at
  )
VALUES
  (
    :package_manager,
    :manifest_type,
    :filename,
    :path,
    :name,
    :latest_git_ref,
    :last_pushed_at,
    :repository_id,
    NOW(),
    NOW()
  )
ON DUPLICATE KEY UPDATE
  id = LAST_INSERT_ID(id),
  name = VALUES(name),
  last_pushed_at = VALUES(last_pushed_at),
  latest_git_ref = VALUES(latest_git_ref),
  updated_at = VALUES(updated_at),
  revision = revision + 1
