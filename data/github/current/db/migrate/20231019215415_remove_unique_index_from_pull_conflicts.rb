class RemoveUniqueIndexFromPullConflicts < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    remove_index :pull_request_conflicts, :pull_request_id, unique: true, name: :index_pull_request_conflicts_on_pr_id
  end
end
