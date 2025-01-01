# typed: strict
# frozen_string_literal: true

class CreateSecretScanningPatternOverrides < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    create_table :secret_scanning_pattern_overrides, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "holds override for a given pattern configuration" do |t|
      t.bigint    :secret_scanning_pattern_config_id, null: false, unsigned: true
      t.string    :version, limit: 27, null: false, comment: "a copy of secret_scanning_pattern_configs.version at the time of the override"
      t.string    :token_type, limit: 255, null: false, comment: "the token type that this override is for"
      t.datetime  :created_at, null: false, precision: 6
      t.datetime  :updated_at, null: false, precision: 6
      t.bigint    :created_by, null: false, unsigned: true
      t.bigint    :updated_by, null: false, unsigned: true
      t.boolean   :push_protected, null: true, default: nil, comment: "whether the pattern is protected by push protection; null inherits the default behavior of the pattern"

      t.index [:secret_scanning_pattern_config_id, :token_type], name: "uq_idx_owner_token_type", unique: true
    end
  end
end
