# typed: true

class DropIssueAlertLinksIdSeq < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::VT)

  def change
    drop_sequence :issue_alert_links_id_seq
    drop_table :issue_alert_links_id_seq
  end
end
