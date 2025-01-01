# rubocop:disable GitHub/ArchivedTable
# typed: true

class AddIndexToPullRequestsForHeadRepoHeadRefStatus < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:head_repository_id, :head_ref, :status], name: "index_pull_requests_on_head_repo_head_ref_and_status"
    end
  end
end

# rubocop:enable GitHub/ArchivedTable
