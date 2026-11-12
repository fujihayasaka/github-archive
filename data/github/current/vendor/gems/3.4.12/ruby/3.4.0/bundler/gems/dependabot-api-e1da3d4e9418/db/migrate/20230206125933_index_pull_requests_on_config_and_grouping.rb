# frozen_string_literal: true

# rubocop:disable Rails/BulkChangeTable
class IndexPullRequestsOnConfigAndGrouping < ActiveRecord::Migration[7.0]
  def change
    add_index :pull_requests, %i(
      update_config_id
      grouped_update
      multiple_dependencies
    ), name: "index_existing_pull_check"
    remove_index :pull_requests, :update_config_id
  end
end
# rubocop:enable Rails/BulkChangeTable
