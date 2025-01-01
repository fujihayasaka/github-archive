# typed: true
# frozen_string_literal: true

class CreateIssueCommentOrchestrationsIdKsIdx < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::IssuesPullRequests)

  def change
    create_table :issue_comment_orchestrations_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_comment_orchestrations_id_ks_idx, :hash, :id

    create_vindex :issue_comment_orchestrations_id_ks_idx, :lookup_unique, owner: "issue_comment_orchestrations", from: "id", table: "issue_comment_orchestrations_id_ks_idx", to: "keyspace_id"
    add_vindex :issue_comment_orchestrations, :issue_comment_orchestrations_id_ks_idx, :id
  end
end
