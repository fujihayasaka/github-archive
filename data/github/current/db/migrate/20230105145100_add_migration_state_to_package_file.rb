# typed: false

# rubocop:disable GitHub/ExistingIdColumnsMustBeBigint
class AddMigrationStateToPackageFile < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Repositories)

  def self.up
    change_table :package_files, bulk: true do |t|
      t.column :migration_state, "enum('unmigrated', 'complete', 'pending', 'error','retriable_error')", null: false, default: "unmigrated"
      t.index [:package_version_id, :migration_state], name: :index_package_files_on_package_version_id_and_migration_state
    end
  end

  def self.down
    change_table :package_files, bulk: true do |t|
      t.remove :migration_state
      t.remove_index name: :index_package_files_on_package_version_id_and_migration_state
    end
  end
end
