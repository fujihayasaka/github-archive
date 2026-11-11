# typed: true
# frozen_string_literal: true

# This migration was generated using `script/generate-vitess-migrations`, for more information please visit https://thehub.github.com/epd/engineering/products-and-services/dotcom/data-partitioning/vitess-for-application-developers/#vitess-migrations-within-the-monolith

class AddKeyspaceForPullRequestGroups < ActiveRecord::Migration[8.1]
  use_connection_class ApplicationRecord::Domain::IssuesPullRequests

  def change
    create_table :pull_request_groups_id_ks_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint(20)", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: false
    end

    # Primary vindex for keyspace table.
    add_vindex :pull_request_groups_id_ks_idx, :hash, :id

    # Lookup vindex for keyspace table. The "owner" table needs to exist before this migration is run.
    create_vindex :pull_request_groups_id_ks_idx, :lookup_unique, owner: "pull_request_groups", from: "id", table: "pull_request_groups_id_ks_idx", to: "keyspace_id", autocommit: true, read_lock: "none"

    # Column vindex for "owner" table. This table needs to exist before this migration is run.
    add_vindex :pull_request_groups, :pull_request_groups_id_ks_idx, :id
  end
end
