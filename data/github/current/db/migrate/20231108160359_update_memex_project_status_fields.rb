class UpdateMemexProjectStatusFields < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def up
    change_table :memex_project_statuses, bulk: true do |t|
      t.change :body, :text, null: true
      t.change :status_value, :json, null: true
      t.index :memex_project_id, name: "index_memex_project_id"
    end
  end

  def down
    change_table :memex_project_statuses, bulk: true do |t|
      t.change :body, :text, null: false
      t.change :status_value, :json, null: false
      t.remove_index name: "index_memex_project_id"
    end
  end
end
