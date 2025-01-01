# typed: strict
# frozen_string_literal: true

class CreateSecretScanningPatternConfig2owner < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def change
    create_table :secret_scanning_pattern_config2owners, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci", comment: "holds the mapping of which owners have which pattern configurations applied" do |t|
      t.bigint    :owner_scope_id, primary_key: true, auto_increment: false, null: false, unsigned: true, comment: "The owner that this config is for"
      t.bigint    :secret_scanning_pattern_config_id, null: false, unsigned: true
      t.datetime  :created_at, null: false, precision: 6
      t.datetime  :updated_at, null: false, precision: 6
      t.bigint    :created_by, null: false, unsigned: true
      t.bigint    :updated_by, null: false, unsigned: true
      t.index [:secret_scanning_pattern_config_id], name: "idx_config_id", comment: "necessary for looking up all of the owners with a given config applied"
    end
  end
end
