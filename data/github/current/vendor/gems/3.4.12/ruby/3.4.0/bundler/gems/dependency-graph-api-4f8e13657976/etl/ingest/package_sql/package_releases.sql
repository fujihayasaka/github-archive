INSERT INTO %package_versions_table_name%
  (
    name,
    package_name,
    package_manager,
    published_at,
    unpublished_at,
    encoded,
    repository_id,
    repository_id_certainty,
    package_id,
    license,
    source_url,
    created_at,
    updated_at
  )
VALUES
  (
    :version,
    :package_name,
    :package_manager,
    :published_at,
    :unpublished_at,
    :encoded,
    :repository_id,
    :repository_id_certainty,
    :package_id,
    :license,
    :source_url,
    NOW(),
    NOW())
ON DUPLICATE KEY UPDATE
  id = LAST_INSERT_ID(id),
  name = VALUES(name),
  package_name = VALUES(package_name),
  package_manager = VALUES(package_manager),
  encoded = VALUES(encoded),
  repository_id = (
    CASE
    WHEN repository_id_certainty <= VALUES(repository_id_certainty)
      THEN VALUES(repository_id)
    ELSE repository_id
    END),
  repository_id_certainty = (
    CASE
    WHEN repository_id_certainty <= VALUES(repository_id_certainty)
      THEN VALUES(repository_id_certainty)
    ELSE repository_id_certainty
    END),
  package_id = VALUES(package_id),
  license = (
    CASE
    WHEN (license IS NULL OR license='') AND (VALUES(license)<>'')
      THEN VALUES(license)
    ELSE license
    END),
  source_url = (
    CASE
    WHEN VALUES(source_url)<>''
      THEN VALUES(source_url)
    ELSE source_url
    END),
  published_at = COALESCE(VALUES(published_at), published_at),
  unpublished_at = COALESCE(VALUES(unpublished_at), unpublished_at),
  updated_at = VALUES(updated_at)
