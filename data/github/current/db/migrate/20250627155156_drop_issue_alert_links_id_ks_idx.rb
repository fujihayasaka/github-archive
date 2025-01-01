# typed: true

class DropIssueAlertLinksIdKsIdx < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    drop_table :issue_alert_links_id_ks_idx, if_exists: true
  end
end
