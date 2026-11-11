# typed: true

# rubocop:disable GitHub/AvoidRedundantIndex

class AddIndexToIssueComments < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_comments, bulk: true do |t|
      t.index [:repository_id, :updated_at, :user_hidden, :user_id, :issue_id], name:  "index_issue_comments_on_repo_updated_user_hidden_user_issue"
    end
  end
end
