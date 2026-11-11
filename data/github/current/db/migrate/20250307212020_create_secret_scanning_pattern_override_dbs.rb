# typed: strict
# frozen_string_literal: true

class CreateSecretScanningPatternOverrideDbs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    create_table :secret_scanning_pattern_override_dbs, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "holds the pre-compiled block database(s) for a given pattern configuration" do |t|
      t.bigint    :secret_scanning_pattern_config_id, unsigned: true, null: false
      t.column    :db_scope, "enum('push_protection_scan', 'job_scan')", null: false
      t.datetime  :latest_override_updated_at, precision: 6, null: true, comment: "secret_scanning_pattern_overrides.updated_at of of the latest pattern override in the DB; useful when back-tracking what patterns exist in the DB"
      t.blob      :compiled_pattern_database, null: true, comment: "the compiled & serialized pattern database for the given owner_scope_id"

      t.index [:secret_scanning_pattern_config_id, :db_scope], name: "uq_idx_owner_token_type", unique: true
    end
  end
end
