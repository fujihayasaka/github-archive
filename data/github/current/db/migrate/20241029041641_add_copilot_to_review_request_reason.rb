# typed: true

class AddCopilotToReviewRequestReason < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_column :review_request_reasons, :reason_type, "enum('codeowners', 'copilot')", null: true, default: nil
    add_column :archived_review_request_reasons, :reason_type, "enum('codeowners', 'copilot')", null: true, default: nil
  end
end
