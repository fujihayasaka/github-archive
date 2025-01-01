# typed: true

class AddUniqueIndexToGuidOnOctoshiftMigrationArchive < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    add_index :octoshift_migration_archives, :guid, unique: true # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
  end
end
