# typed: true
# frozen_string_literal: true

class CreatePinnedIssueCommentsIdKsIdx < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :pinned_issue_comments_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    # Primary vindex for keyspace table.
    add_vindex :pinned_issue_comments_id_ks_idx, :hash, :id

    # Lookup vindex for keyspace table.
    create_vindex :pinned_issue_comments_id_ks_idx, :lookup_unique, owner: "pinned_issue_comments", from: "id", table: "pinned_issue_comments_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    # Column vindex for "owner" table.
    add_vindex :pinned_issue_comments, :pinned_issue_comments_id_ks_idx, :id
  end
end
