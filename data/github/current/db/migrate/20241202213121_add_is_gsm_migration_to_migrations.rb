# typed: true
# frozen_string_literal: true

class AddIsGsmMigrationToMigrations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Migrations)

  def change
    add_column :migrations, :is_gsm_migration, :boolean, default: false, null: false
  end
end
