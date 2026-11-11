# typed: true

class AddReadPctToElastomerIndexMemo < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Search)

  def change
    change_table :elastomer_index_memos, bulk: true do |t|
      t.integer :read_pct, null: false, default: 0, limit: 1, unsigned: true
    end
  end
end
