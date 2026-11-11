# typed: true
# frozen_string_literal: true

class CreateIssueFieldValuesIdKsIdx < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :issue_field_values_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_field_values_id_ks_idx, :hash, :id

    create_vindex :issue_field_values_id_ks_idx, :lookup_unique, owner: "issue_field_values", from: "id", table: "issue_field_values_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    add_vindex :issue_field_values, :issue_field_values_id_ks_idx, :id
    add_vindex :issue_field_values, :issues_id_ks_idx, :issue_id
  end
end
