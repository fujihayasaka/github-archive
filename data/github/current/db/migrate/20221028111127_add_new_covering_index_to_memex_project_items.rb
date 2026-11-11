# typed: true

class AddNewCoveringIndexToMemexProjectItems < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    add_index :memex_project_items, [:memex_project_id, :content_id, :content_type], unique: true, name: "index_memex_items_on_project_and_content"
  end
end
