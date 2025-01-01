# typed: true

class AddFixedToCodeScanningReviewComment < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    add_column :code_scanning_review_comments, :fixed, :boolean
  end
end
