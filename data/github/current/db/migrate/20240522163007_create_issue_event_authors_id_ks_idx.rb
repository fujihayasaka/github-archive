class CreateIssueEventAuthorsIdKsIdx < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_event_authors_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_event_authors_id_ks_idx, :hash, :id
    create_vindex :issue_event_authors_id_ks_idx, :lookup_unique, owner: "issue_event_authors", from: "id", table: "issue_event_authors_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"
    add_vindex :issue_event_authors, :issue_events_id_ks_idx, :issue_event_id
    add_vindex :issue_event_authors, :issue_event_authors_id_ks_idx, :id
  end
end
