# typed: true

class AddGuidToOctoshiftMigrationArchivesTable < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    change_table :octoshift_migration_archives, bulk: true do |t|
      t.column :guid, :string, limit: 36, null: false
      t.index [:guid, :organization_id]
    end
  end
end
