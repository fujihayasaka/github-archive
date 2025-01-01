# typed: true
class CreatePullRequestReviewCommentOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :pull_request_review_comment_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :pull_request_id, unsigned: true, null: true
      t.bigint :pull_request_review_comment_id, unsigned: true, null: true
      t.bigint :repository_id, unsigned: true, null: false
      t.string :type, null: false, limit: 59
      t.integer :state, null: false, default: 0
      t.string :step_name, limit: 70
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.bigint :parent_id, unsigned: true, null: true
      t.string :error_message, null: true
      t.timestamps
    end

    add_vindex :pull_request_review_comment_orchestrations, :hash, :repository_id
    add_vindex :pull_request_review_comment_orchestrations, :pull_requests_id_ks_idx, :pull_request_id
    add_vindex :pull_request_review_comment_orchestrations, :pull_request_review_comments_id_ks_idx, :pull_request_review_comment_id

    add_auto_increment(:pull_request_review_comment_orchestrations, :id, :pull_request_review_comment_orchestrations_id_seq)
  end
end
