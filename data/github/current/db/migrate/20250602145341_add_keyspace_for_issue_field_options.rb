# typed: true
# frozen_string_literal: true

# This migration was generated using `script/generate-vitess-migrations`, for more information please visit https://thehub.github.com/epd/engineering/products-and-services/dotcom/data-partitioning/vitess-for-application-developers/#vitess-migrations-within-the-monolith

class AddKeyspaceForIssueFieldOptions < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::IssuesPullRequests)

  def change
    create_table :issue_field_options_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    add_vindex :issue_field_options_id_ks_idx, :hash, :id

    create_vindex :issue_field_options_id_ks_idx, :lookup_unique, owner: "issue_field_options", from: "id", table: "issue_field_options_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    add_vindex :issue_field_options, :issue_field_options_id_ks_idx, :id
    add_vindex :issue_field_options, :issue_fields_id_ks_idx, :issue_field_id
  end
end
