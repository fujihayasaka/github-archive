# typed: true

class AddIssueEventAuthorsUserHiddenIndex < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    change_table :issue_event_authors, bulk: true do |t|
      t.index [:user_hidden, :author_id], name: "index_issue_event_authors_on_user_hidden_and_author_id"
    end
  end
end
