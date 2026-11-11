# typed: true

class UseBigintForOctoshiftMigrationArchiveSize < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    change_column :octoshift_migration_archives, :size, :bigint, null: false
  end
end
