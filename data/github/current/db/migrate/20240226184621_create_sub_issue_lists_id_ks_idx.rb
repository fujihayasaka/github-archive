class CreateSubIssueListsIdKsIdx < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :sub_issue_lists_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :sub_issue_lists_id_ks_idx, :hash, :id

    create_vindex :sub_issue_lists_id_ks_idx, :lookup_unique, owner: "sub_issue_lists", from: "id", table: "sub_issue_lists_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"
    add_vindex :sub_issue_lists, :issues_id_ks_idx, :issue_id
    add_vindex :sub_issue_lists, :sub_issue_lists_id_ks_idx, :id
  end
end
