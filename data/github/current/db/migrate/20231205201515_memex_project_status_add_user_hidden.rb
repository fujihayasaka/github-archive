class MemexProjectStatusAddUserHidden < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table :memex_project_statuses, bulk: true do |t|
      t.boolean :user_hidden, null: false, default: false
      t.index [:user_hidden, :creator_id], name: "index_user_hidden_and_creator_id"
    end
  end

  def down
    change_table :memex_project_statuses, bulk: true do |t|
      t.remove :user_hidden
      t.remove_index [:user_hidden, :creator_id], name: "index_user_hidden_and_creator_id"
    end
  end
end
