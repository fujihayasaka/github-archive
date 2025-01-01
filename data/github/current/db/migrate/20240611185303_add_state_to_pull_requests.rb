class AddStateToPullRequests < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    add_column :pull_requests, :state, "enum('closed','open')", collation: :utf8mb3_general_ci
    add_column :archived_pull_requests, :state, "enum('closed','open')", collation: :utf8mb3_general_ci
  end
end
