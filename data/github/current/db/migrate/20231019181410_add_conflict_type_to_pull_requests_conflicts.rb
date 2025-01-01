class AddConflictTypeToPullRequestsConflicts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    add_column :pull_request_conflicts, :conflict_type, :tinyint, null: false, default: 0
  end
end
