# typed: true
class DropIssueEditsDiffColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    remove_column :issue_edits, :diff
  end
end
