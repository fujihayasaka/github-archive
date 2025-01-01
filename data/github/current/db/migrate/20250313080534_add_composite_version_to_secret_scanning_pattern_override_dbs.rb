# typed: strict
# frozen_string_literal: true

class AddCompositeVersionToSecretScanningPatternOverrideDbs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def up
    change_table :secret_scanning_pattern_override_dbs, bulk: true do |t|
      t.column :composite_version, "char(64)", null: false, charset: "ascii", collation: "ascii_general_ci", comment: "A sha256 hash of the pattern config version and the version of all custom patterns included in the db compilation"
      t.remove :latest_override_updated_at
    end
  end

  sig { void }
  def down
    change_table :secret_scanning_pattern_override_dbs, bulk: true do |t|
      t.datetime :latest_override_updated_at, precision: 6, null: true, comment: "secret_scanning_pattern_overrides.updated_at of the latest pattern override in the DB; useful when back-tracking what patterns exist in the DB"
      t.remove   :composite_version
    end
  end
end
