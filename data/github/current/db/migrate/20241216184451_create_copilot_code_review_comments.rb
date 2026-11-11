# typed: true
# frozen_string_literal: true

class CreateCopilotCodeReviewComments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :copilot_code_review_comments, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :copilot_coding_guideline_id, unsigned: true, null: true
      t.references :subject, polymorphic: true, null: false
      t.timestamps

      t.index [:copilot_coding_guideline_id, :subject_id, :subject_type]
    end

    add_vindex :copilot_code_review_comments, :hash, :repository_id
    add_auto_increment :copilot_code_review_comments, :id, :copilot_code_review_comments_id_seq
  end
end
