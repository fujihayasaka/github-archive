# typed: true

class DropRawDataFromIssueEvents < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    remove_column :issue_events, :raw_data, :blob
    remove_column :archived_issue_events, :raw_data, :blob
  end
end
