# typed: strict
# frozen_string_literal: true

class CreateAuditSecretScanningPatternOverrides < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    create_table :audit_secret_scanning_pattern_overrides, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "historical mutable columns from secret_scanning_pattern_overrides" do |t|
      t.bigint    :secret_scanning_pattern_overrides_id, null: false, unsigned: true, comment: "the id of the secret_scanning_pattern_overrides row that was updated"
      t.string    :token_type, limit: 255, null: false
      t.string    :version, limit: 27, null: false
      t.datetime  :active_from, null: false, precision: 6
      t.bigint    :updated_by, null: false, unsigned: true
      t.boolean   :push_protected, null: true, default: nil

      t.index [:secret_scanning_pattern_overrides_id, :token_type, :active_from], name: "uq_idx_override_id_token_type_active_from", unique: true
    end
  end
end
