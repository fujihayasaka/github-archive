# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex
# rubocop:disable GitHub/ArchivedTable#GitHub/ArchivedTable

class AddIndexPrsOnHeadRepoIdHeadRefRepoIdUserHiddenUserId < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_requests, bulk: true do |t|
      t.index [:head_repository_id, :head_ref, :repository_id, :user_hidden, :user_id], name:  "index_prs_on_head_repo_id_head_ref_repo_id_user_hidden_user_id"
    end
  end
end
