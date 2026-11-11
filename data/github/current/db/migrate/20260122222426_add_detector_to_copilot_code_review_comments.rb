# typed: true
# frozen_string_literal: true

class AddDetectorToCopilotCodeReviewComments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_column :copilot_code_review_comments, :copilot_detector,
      :string,
      limit: 50,
      null: true,
      default: nil
  end
end
