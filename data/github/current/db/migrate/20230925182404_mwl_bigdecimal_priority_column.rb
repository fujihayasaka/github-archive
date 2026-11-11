class MwlBigdecimalPriorityColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_items, bulk: true do |t|
      t.column :mwl_priority, :decimal, precision: 35, scale: 30, null: true
      t.index [:memex_project_id, :mwl_priority], name: "index_memex_project_items_on_memex_project_id_and_mwl_priority", unique: true
    end
  end
end
