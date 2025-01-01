INSERT INTO %repositories_table_name%
  (
    github_repository_id,
    github_owner_id,
    nwo,
    public,
    created_at,
    updated_at
  )
VALUES
  (
    :github_repository_id,
    :github_owner_id,
    :nwo,
    :visibility_public,
    NOW(),
    NOW()
  )
ON DUPLICATE KEY UPDATE
  id = LAST_INSERT_ID(id),
  github_owner_id = VALUES(github_owner_id),
  nwo = VALUES(nwo),
  public = VALUES(public),
  updated_at = VALUES(updated_at)
