# typed: true

class CreateBusinessCredentialAuthorizations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Users)

  def up
    create_table :business_credential_authorizations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t| # rubocop:disable GitHub/NoNewTablesOnSharedDbClusters
      t.bigint :business_id, unsigned: true, null: false
      t.bigint :credential_id, unsigned: true, null: false
      t.string :credential_type, null: false, limit: 30
      t.bigint :actor_id, unsigned: true, null: false
      t.string :actor_type, null: false, limit: 30
      t.datetime :created_at, null: false, precision: 6
      t.datetime :updated_at, null: false, precision: 6
      t.datetime :revoked_at, null: true, precision: 6
      t.bigint :revoked_by_id, unsigned: true, null: true
      t.binary :fingerprint_sha256, null: true, limit: 96
      t.integer :is_application, null: false, default: 0, limit: 1
    end
  end

  def down
    drop_table :business_credential_authorizations
  end
end
