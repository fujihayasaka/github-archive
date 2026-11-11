# typed: true

# rubocop:disable GitHub/ArchivedTable, GitHub/AvoidRedundantIndex
class AddIndexCreatedAtToIssueComments < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    change_table :issue_comments, bulk: true do |t|
      t.index [:repository_id, :created_at, :updated_at, :user_hidden, :user_id, :issue_id], name:  "idx_ic_repo_created_updated_userhidden_user_id_issue_id"
    end
  end
end
# rubocop:enable GitHub/ArchivedTable, GitHub/AvoidRedundantIndex
