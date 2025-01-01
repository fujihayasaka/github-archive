class AddImportMigrationSourceToMigrations < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Migrations

  def change
    change_table :migrations, bulk: true do |t|
      t.string :import_migration_source, limit: 30, null: true
    end
  end
end
