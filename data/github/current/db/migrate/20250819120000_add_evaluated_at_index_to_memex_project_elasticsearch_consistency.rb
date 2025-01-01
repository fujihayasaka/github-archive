# typed: true
# frozen_string_literal: true

class AddEvaluatedAtIndexToMemexProjectElasticsearchConsistency < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Memexes)
  def up
    add_index :memex_project_elasticsearch_consistency,
              [:index_name, :evaluated_at],
              name: :idx_index_name_evaluated_at,
              order: { evaluated_at: :desc }
  end

  def down
    remove_index :memex_project_elasticsearch_consistency, name: :idx_index_name_evaluated_at
  end
end
