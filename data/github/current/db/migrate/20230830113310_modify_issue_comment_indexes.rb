# typed: true

class ModifyIssueCommentIndexes < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_comments, bulk: true do |t|
      t.remove_index name: :index_issue_comments_on_repository_id_and_updated_at
      t.remove_index name: :index_issue_comments_on_repo_updated_user_hidden_user_issue

      t.index [:repository_id, :updated_at, :id, :user_hidden, :user_id, :issue_id], name:  "index_issue_comments_on_repo_updated_id_user_hidden_user_issue"
    end
  end
end
