class CleanupIndexManifestDepSpecPkgName < ActiveRecord::Migration[7.0]
  # This index was removed in an earlier migration (see link) but due to
  # the two-step migration, in GHES sometimes only the "add index" step:
  # https://github.com/github/dependency-graph-api/blob/master/db/migrate/20211129230519_add_requirements_to_unique_index.rb#L3-L6
  # was completed, and the "remove index" step was skipped manually:
  # https://github.com/github/dependency-graph-api/blob/master/db/migrate/20211129230519_add_requirements_to_unique_index.rb#L8
  #
  # This migration is a best-effort cleanup to remove the old index from the table, if
  # found in GHES instances during 3.7 -> 3.8 upgrades in the future. As seen on a customer
  # instance recently during an upgrade: https://github.com/github/dependency-graph/issues/2382
  #
  # This is a harmless change, and should be a no-op in most cases (we haven't seen it elsewhere)
  def change
    remove_index :dg_manifest_dependencies, name: :manifest_dep_spec_package_name, if_exists: true
  end
end
