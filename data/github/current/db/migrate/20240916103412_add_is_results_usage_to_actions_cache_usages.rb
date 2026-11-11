# typed: true
# frozen_string_literal: true

class AddIsResultsUsageToActionsCacheUsages < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Billing)

  def change
    change_table :actions_cache_usages, bulk: true do |t|
      t.column :is_results_usage, :boolean, default: false, null: false, comment: "Whether or not the cache usage comes from result service"
      t.remove_index [:repository_id], name: "index_actions_cache_usages_on_repository_id"
      t.index [:repository_id, :is_results_usage], unique: true, name: "index_actions_cache_usages_on_repository_id_and_is_results_usage", comment: "Index for finding all cache usages for a repository and system that published it"
    end
  end
end
