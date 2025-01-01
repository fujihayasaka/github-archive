# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewCommentFeedbacks < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :copilot_code_review_comment_feedbacks, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :copilot_code_review_comment_id, unsigned: true, null: false
      t.bigint :feedback_author_id, unsigned: true, null: false
      t.integer :feedback_type, null: false, limit: 1, default: 0
      t.integer :feedback_choice, null: true, limit: 1, default: nil
      t.string :text_response, null: true
      t.timestamps

      t.index :copilot_code_review_comment_id
      t.index :feedback_type
    end

    add_vindex :copilot_code_review_comment_feedbacks, :hash, :repository_id
    add_auto_increment :copilot_code_review_comment_feedbacks, :id, :copilot_code_review_comment_feedbacks_id_seq
  end
end
