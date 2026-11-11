# typed: true

class DropStateFromPullRequests < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    remove_column :pull_requests, :state, "enum('closed','open')", collation: :utf8mb3_general_ci
    remove_column :archived_pull_requests, :state, "enum('closed','open')", collation: :utf8mb3_general_ci
  end
end
