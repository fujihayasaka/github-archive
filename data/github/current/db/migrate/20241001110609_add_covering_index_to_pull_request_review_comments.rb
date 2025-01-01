# typed: true

# rubocop:disable GitHub/ArchivedTable
class AddCoveringIndexToPullRequestReviewComments < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def up
    change_table :pull_request_review_comments, bulk: true do |t|
      t.remove_index name: "index_pr_review_comments_on_repo_state_created_at"
      t.index [:repository_id, :state, :created_at, :id, :user_hidden, :user_id], name: "pr_review_comments_repo_state_created_at_id_user_hidden_user_id"
    end
  end

  def down
    change_table :pull_request_review_comments, bulk: true do |t|
      t.remove_index name: "pr_review_comments_repo_state_created_at_id_user_hidden_user_id"
      t.index [:repository_id, :state, :created_at], name: "index_pr_review_comments_on_repo_state_created_at"
    end
  end
end
# rubocop:enable GitHub/ArchivedTable
