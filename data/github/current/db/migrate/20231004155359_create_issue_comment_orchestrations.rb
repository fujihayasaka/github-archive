# typed: true
# frozen_string_literal: true

class CreateIssueCommentOrchestrations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_comment_orchestrations, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :issue_id, unsigned: true, null: true
      t.bigint :issue_comment_id, unsigned: true, null: true
      t.bigint :repository_id, unsigned: true, null: false
      t.string :type, null: false, limit: 47
      t.integer :state, null: false, default: 0
      t.string :step_name, limit: 70
      t.text :data
      t.integer :attempts, null: false, default: 0
      t.bigint :parent_id, unsigned: true, null: true
      t.string :error_message, null: true
      t.timestamps

      t.index [:state, :updated_at], name: "index_state_updated_at"
      t.index [:updated_at], name: "index_updated_at"
    end

    add_vindex :issue_comment_orchestrations, :hash, :repository_id
    add_vindex :issue_comment_orchestrations, :issues_id_ks_idx, :issue_id
    add_vindex :issue_comment_orchestrations, :issue_comments_id_ks_idx, :issue_comment_id

    add_auto_increment(:issue_comment_orchestrations, :id, :issue_comment_orchestrations_id_seq)
  end
end
