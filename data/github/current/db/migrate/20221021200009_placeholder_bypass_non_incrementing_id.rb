# typed: true
class PlaceholderBypassNonIncrementingId < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::TokenScanningService)

  def up
    change_table(:secret_scanning_push_protections_bypass_placeholders, bulk: true) do |t|
      t.column :ksuid, "char(27) CHARACTER SET ascii", null: false,  comment: "a ksuid that identifies this record - to be used to construct urls with non-incrementing ids"
      t.index :ksuid, name: "idx_ksuid"
    end
  end

  def down
    change_table(:secret_scanning_push_protections_bypass_placeholders, bulk: true) do |t|
      t.remove_index name: "idx_ksuid"
      t.remove :ksuid
    end
  end
end
