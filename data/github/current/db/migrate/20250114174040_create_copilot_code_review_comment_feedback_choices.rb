# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewCommentFeedbackChoices < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :copilot_code_review_comment_feedback_choices, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :copilot_code_review_comment_feedback_id, unsigned: true, null: false
      t.integer :choice, null: true, limit: 1, default: nil
      t.timestamps

      t.index :copilot_code_review_comment_feedback_id
    end

    add_vindex :copilot_code_review_comment_feedback_choices, :hash, :repository_id
    add_auto_increment :copilot_code_review_comment_feedback_choices, :id, :copilot_code_review_comment_feedback_choices_id_seq
  end
end
