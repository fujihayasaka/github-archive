# typed: true

class MemexProjectItemBlocked < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_items, bulk: true do |t|
      t.column :blocked_by_count, :integer, unsigned: true
      t.column :blocking_count, :integer, unsigned: true
    end
  end
end
