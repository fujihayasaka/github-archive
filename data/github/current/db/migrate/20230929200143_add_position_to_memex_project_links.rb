class AddPositionToMemexProjectLinks < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::Memexes

  def change
    change_table :memex_project_links, bulk: true do |t|
      t.integer :position, null: true

      t.index [:source_id, :source_type, :position]
    end
  end
end
