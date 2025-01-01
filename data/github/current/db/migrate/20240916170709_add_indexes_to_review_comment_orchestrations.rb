# typed: true
class AddIndexesToReviewCommentOrchestrations < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :pull_request_review_comment_orchestrations, bulk: true do |t|
      t.index [:repository_id, :pull_request_id, :type, :state], name: "index_pr_comment_orchestrations_on_repo_id_pull_id_type_state"
      t.index [:state, :updated_at], name: "index_pr_comment_orchestrations_on_state_updated_at"
      t.index [:updated_at]
    end
  end
end
