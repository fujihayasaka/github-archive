# typed: strict
# frozen_string_literal: true

class AddNumberToSecretScanningPatternConfigs < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  sig { void }
  def up
    change_table :secret_scanning_pattern_configs, bulk: true do |t|
      t.integer :number, unsigned: true, null: false
      t.change  :version, "char(27)", null: false, charset: "ascii", collation: "ascii_general_ci", comment: "ksuid; this changes when any of the underlying pattern overrides are changed."
      # table is empty so we can add a unique index without a problem
      # rubocop:disable GitHub/DoNotAddUniqueIndexToExistingColumn
      t.index   [:owner_scope_id, :number], unique: true, name: "uq_idx_owner_number"
    end
  end

  sig { void }
  def down
    change_table :secret_scanning_pattern_configs, bulk: true do |t|
      t.remove :number
      t.change :version, "varchar(27)", null: false, comment: "ksuid; this changes when any of the underlying pattern overrides are changed."
      t.remove_index [:owner_scope_id, :number], name: "uq_idx_owner_number"
    end
  end
end
