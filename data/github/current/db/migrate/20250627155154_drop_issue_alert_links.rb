# typed: true

class DropIssueAlertLinks < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    drop_table :issue_alert_links, if_exists: true
  end
end
