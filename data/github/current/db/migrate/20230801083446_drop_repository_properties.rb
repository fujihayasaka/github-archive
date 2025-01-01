# typed: true

class DropRepositoryProperties < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    drop_table :repository_properties
  end
end
