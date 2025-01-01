# typed: true

class AddIndexToPullRequestReviewComments < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_index :pull_request_review_comments, [:repository_id, :state, :created_at], name: "index_pr_review_comments_on_repo_state_created_at"
  end
end
