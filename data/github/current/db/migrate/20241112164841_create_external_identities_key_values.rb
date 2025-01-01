# typed: true
# frozen_string_literal: true

class CreateExternalIdentitiesKeyValues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def change
    create_table :external_identities_key_values, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.string :key, limit: 255, null: false
      t.blob :value, null: false
      t.timestamps
      t.datetime :expires_at, null: true, precision: 6

      t.index :key, unique: true
      t.index :expires_at
    end
  end
end
