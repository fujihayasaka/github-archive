# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/EnsureDomainIsolationInMigration

class CreateExternalIdentitiesKeyValuesOnAuthnd < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Authnd)

  def change
    return unless (Rails.env.test? || Rails.env.development?) && !GitHub.enterprise? # rubocop:disable GitHub/DoNotBranchOnRailsEnv

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
