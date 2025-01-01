# typed: true

class CreateSecretScanningPushProtectionsBypassPlaceholders < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)
  def change
    create_table :secret_scanning_push_protections_bypass_placeholders, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.datetime :created_at, null: false, precision: 6, comment: "when the placeholder was created"
      t.string :signature, null: false, limit: 64, comment: "the hex encoded sha256 hash of the raw secret that should be allowed into the remotes"
      t.string :token_type, null: false, limit: 64, comment: "the type of token that should be allowed into the remotes"
      t.bigint :owner_scope_id, null: false, unsigned: true, comment: "the scope that this bypass placeholder applies to"
      t.index [:owner_scope_id, :token_type, :signature], unique: true, name: "idx_scope_type_signature"
      t.index :created_at, name: "idx_created"
    end
  end
end
