INSERT INTO %star_counts_table_name%
  (
    github_repository_id,
    star_count
  )
VALUES
  (
    :github_repository_id,
    :star_count
  )
ON DUPLICATE KEY UPDATE
  id = LAST_INSERT_ID(id),
  star_count = VALUES(star_count)
