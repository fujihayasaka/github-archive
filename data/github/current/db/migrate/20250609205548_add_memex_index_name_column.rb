# typed: true
# frozen_string_literal: true

class AddMemexIndexNameColumn < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)
  def change
    change_table :memex_project_elasticsearch_consistency, bulk: true do |t|
      t.column :index_name, "varbinary(128)", null: true

      # Add the new composite indexes
      t.index [:memex_project_id, :index_name], unique: true, name: "idx_memex_project_id_and_index_name"
      t.index [:index_name, :consistency], name: "idx_consistency_and_index_name" # rubocop:disable GitHub/AvoidRedundantIndex
    end
  end
end
