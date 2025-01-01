# typed: true
# frozen_string_literal: true

class AddCopilotInstructionTypeToCopilotCodeReviewComments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)
  def change
    add_column :copilot_code_review_comments, :copilot_instruction_type,
        "enum('repo', 'org')",
            null: true,
            default: nil
  end
end
