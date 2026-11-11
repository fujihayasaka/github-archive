# typed: strict
# frozen_string_literal: true

class CreateSecretScanningPatternConfigs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    create_table :secret_scanning_pattern_configs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint    :owner_scope_id, null: false, unsigned: true, comment: "The owner that this config is for"
      t.string    :name, limit: 255, null: false
      t.string    :version, limit: 27, null: false, comment: "ksuid; this changes when any of the underlying pattern overrides are changed."
      t.datetime  :created_at, null: false, precision: 6
      t.datetime  :updated_at, null: false, precision: 6
      t.datetime  :deleted_at, null: true, precision: 6, default: nil
      t.bigint    :created_by, null: false, unsigned: true
      t.bigint    :updated_by, null: false, unsigned: true
      t.bigint    :deleted_by, null: true, unsigned: true, default: nil

      t.index [:owner_scope_id, :name], name: "uq_idx_owner_name", unique: true
      t.index [:owner_scope_id, :deleted_at], name: "idx_owner_scope"
    end
  end
end
