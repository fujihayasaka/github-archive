# frozen_string_literal: true

# This migration reclaims disk space for deleted rows in the `dg_abstract_repository_dependencies` and `dg_manifests` tables.
# The `repository_id` column in these tables is currently an integer; the database team recommends changing it to a bigint to prevent future ID overflow.
class ChangeRepositoryIdToBigint < ActiveRecord::Migration[7.1]

  def up
    execute "ALTER TABLE dg_abstract_repository_dependencies MODIFY COLUMN repository_id bigint UNSIGNED NOT NULL"
    execute "ALTER TABLE dg_build_types MODIFY COLUMN repository_id bigint UNSIGNED NOT NULL"
    execute "ALTER TABLE dg_manifests MODIFY COLUMN repository_id bigint UNSIGNED DEFAULT NULL"
    execute "ALTER TABLE dg_package_versions MODIFY COLUMN repository_id bigint UNSIGNED DEFAULT NULL"
    execute "ALTER TABLE dg_packages MODIFY COLUMN repository_id bigint UNSIGNED DEFAULT NULL"
    execute "ALTER TABLE dg_snapshots MODIFY COLUMN repository_id bigint UNSIGNED NOT NULL"
  end

  def down
    execute "ALTER TABLE dg_abstract_repository_dependencies MODIFY COLUMN repository_id int NOT NULL"
    execute "ALTER TABLE dg_build_types MODIFY COLUMN repository_id int NOT NULL"
    execute "ALTER TABLE dg_manifests MODIFY COLUMN repository_id int DEFAULT NULL"
    execute "ALTER TABLE dg_package_versions MODIFY COLUMN repository_id int DEFAULT NULL"
    execute "ALTER TABLE dg_packages MODIFY COLUMN repository_id int DEFAULT NULL"
    execute "ALTER TABLE dg_snapshots MODIFY COLUMN repository_id int NOT NULL"
  end
end
