# typed: true
class AddMemexViewSliceBy < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)

  def change
    change_table :memex_project_views, bulk: true do |t|
      t.column :slice_by, "json DEFAULT NULL"
    end
  end
end
