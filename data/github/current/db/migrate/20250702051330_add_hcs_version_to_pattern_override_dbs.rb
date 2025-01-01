# typed: true
# frozen_string_literal: true

class AddHcsVersionToPatternOverrideDbs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def change
    change_table :secret_scanning_pattern_override_dbs, bulk: true do |t|
      t.column :hcs_changelog_version, :string, limit: 255, null: true, comment: "The HCS changelog version that was used to compile this scan db"
      t.index :hcs_changelog_version, unique: false, name: "idx_hcs_version"
    end
  end
end
