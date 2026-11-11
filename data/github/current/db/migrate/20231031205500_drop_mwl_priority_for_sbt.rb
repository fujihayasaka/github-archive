class DropMwlPriorityForSbt < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table :memex_project_items, bulk: true do |t|
      t.remove :mwl_priority
      t.remove_index [:memex_project_id, :mwl_priority]
    end
  end

  def down
    change_table :memex_project_items, bulk: true do |t|
      t.column :mwl_priority, :decimal, null: true, scale: 35, precision: 30
      t.index [:memex_project_id, :mwl_priority], name: "index_memex_project_items_on_memex_project_id_and_mwl_priority"
    end
  end
end
