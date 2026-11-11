# typed: true
# frozen_string_literal: true

class RemoveMemexProjectIdIndexFromConsistencyTable < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)
  def up
    remove_index :memex_project_elasticsearch_consistency, name: :idx_on_memex_project_id_c835b7f4ac
  end

  def down
    add_index :memex_project_elasticsearch_consistency, :memex_project_id, name: :idx_on_memex_project_id_c835b7f4ac, unique: true
  end
end
