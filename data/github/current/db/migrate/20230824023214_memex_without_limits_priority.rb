class MemexWithoutLimitsPriority < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_items, bulk: true do |t|
      t.column :mwl_priority, :float, default: 0, null: false
      t.index [:memex_project_id, :mwl_priority], name: "index_memex_project_items_on_memex_project_id_and_mwl_priority"
      t.index [:memex_project_id, :archived_at, :mwl_priority], name: "memex_project_items_on_project_id_archived_at_and_mwl_priority"
    end
  end
end
