# typed: true

class AddIndexToIssues < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issues, bulk: true do |t|
      t.index [:repository_id, :updated_at, :id, :has_pull_request, :state, :user_hidden, :user_id], name:  "index_issues_repo_updated_at_id_pr_state_user_hidden_user"
    end
  end
end
