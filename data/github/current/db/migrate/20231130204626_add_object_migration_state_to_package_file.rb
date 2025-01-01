class AddObjectMigrationStateToPackageFile < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Packages)

  def self.up
    change_table :package_files, bulk: true do |t|
      t.column :object_migration_state, "enum('unmigrated', 'complete')", null: false, default: "unmigrated"
      t.index :object_migration_state, name: :index_package_files_on_object_migration_state
      # Change columns to bigint unsigned to fix linting error:
      t.change :id, :bigint, null: false, unsigned: true
      t.change :package_version_id, :bigint, null: false, unsigned: true
      t.change :storage_blob_id, :bigint, unsigned: true, default: nil
      t.change :uploader_id, :bigint, unsigned: true, default: nil
    end
  end

  def self.down
    change_table :package_files, bulk: true do |t|
      t.remove :object_migration_state
      t.remove_index name: :index_package_files_on_object_migration_state
      # Roll back bigint unsigned change
      t.change :id, :int, null: false
      t.change :package_version_id, :int, null: false
      t.change :storage_blob_id, :int, default: nil
      t.change :uploader_id, :int, default: nil
    end
  end
end
