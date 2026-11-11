class PullRequestStacksChangeNumberColumnNull < ActiveRecord::Migration[8.2]
  use_connection_class ApplicationRecord::IssuesPullRequests

  def change
    change_column_null :pull_request_stacks, :number, false
  end
end
