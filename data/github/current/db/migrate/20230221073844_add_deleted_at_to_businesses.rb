# typed: true
class AddDeletedAtToBusinesses < ActiveRecord::Migration[7.1]
  def change
    reversible do |dir|
      change_table :businesses, bulk: true do |t|
        dir.up do
          t.datetime :deleted_at, null: true, precision: 6
          t.index :deleted_at
        end

        dir.down do
          t.remove :deleted_at
          t.remove_index :deleted_at
        end
      end
    end
  end
end
