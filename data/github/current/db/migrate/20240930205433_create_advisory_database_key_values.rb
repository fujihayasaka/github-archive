# typed: true
# frozen_string_literal: true

class CreateAdvisoryDatabaseKeyValues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    create_table :advisory_database_key_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :key, limit: 255, null: false # rubocop:disable GitHub/NoReservedMySQLKeywordsPresentInMigration
      t.blob :value, null: false
      t.timestamps
      t.datetime :expires_at, null: true, precision: 6

      t.index :key, unique: true # rubocop:disable GitHub/NoReservedMySQLKeywordsPresentInMigration
      t.index :expires_at
    end
  end
end
