# typed: true

# rubocop:disable GitHub/ArchivedTable

class AddRepoStatusFilterIndexToPullRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:repository_id, :status, :merged_at, :base_repository_id, :base_ref, :user_hidden, :user_id, :created_at, :updated_at], name: "idx_pr_filters"
    end
  end

end

# rubocop:enable GitHub/ArchivedTable
