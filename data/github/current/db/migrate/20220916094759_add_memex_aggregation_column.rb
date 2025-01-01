# typed: true

class AddMemexAggregationColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Memex)

  def change
    change_table :memex_project_views, bulk: true do |t|
      t.column :aggregation_settings, "json DEFAULT NULL"
    end
  end
end
