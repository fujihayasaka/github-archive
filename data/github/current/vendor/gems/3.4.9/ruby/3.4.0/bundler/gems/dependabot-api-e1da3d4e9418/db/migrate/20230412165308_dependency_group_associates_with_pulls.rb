# frozen_string_literal: true

# rubocop:disable Rails/BulkChangeTable
class DependencyGroupAssociatesWithPulls < ActiveRecord::Migration[7.0]
  def change
    add_column :pending_pull_requests, :dependency_group_id, :bigint
    add_column :pull_requests, :dependency_group_id, :bigint
    add_index :pull_requests, :dependency_group_id
  end
end
# rubocop:enable Rails/BulkChangeTable
