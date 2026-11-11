# typed: true

class AddProblemTypeToAutomatedReviewComments < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_column :automated_review_comments, :problem_type, :string, null: true, limit: 255
  end
end
