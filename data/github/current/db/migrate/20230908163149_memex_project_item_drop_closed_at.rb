class MemexProjectItemDropClosedAt < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_items, bulk: true do |t|
      t.remove :closed_at
    end
  end
end
