# typed: true

class AddRepoStateUpdatedAtUserHiddenUserIndexToPullRequestReviewComments < ActiveRecord::Migration[7.1]
  use_connection_class ApplicationRecord::Domain::IssuesPullRequests

  def change
    change_table :pull_request_review_comments, bulk: true do |t|
      t.change :id, :bigint, unsigned: true
      t.change :pull_request_id, :bigint, unsigned: true
      t.change :pull_request_review_thread_id, :bigint, unsigned: true
      t.change :pull_request_review_id, :bigint, unsigned: true
      t.change :reply_to_id, :bigint, unsigned: true
      t.change :user_id, :bigint, unsigned: true
      t.change :repository_id, :bigint, unsigned: true

      t.index [:repository_id, :state, :updated_at, :user_hidden, :user_id],
        name: "index_pr_review_comments_on_repo_state_updated_user_hidden_user"
    end
  end
end
