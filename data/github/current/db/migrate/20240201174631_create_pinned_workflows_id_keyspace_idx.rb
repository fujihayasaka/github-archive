# typed: true
# frozen_string_literal: true
class CreatePinnedWorkflowsIdKeyspaceIdx < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :pinned_workflows_id_keyspace_idx, id: false, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :id, "bigint", primary_key: true, auto_increment: false, unsigned: true, null: false, default: nil
      t.column :keyspace_id, "varbinary(128)", null: true
    end

    add_vindex :pinned_workflows_id_keyspace_idx, :hash, :id
    create_vindex :pinned_workflows_id_keyspace_idx, :lookup_unique, owner: "pinned_workflows", from: "id", table: "pinned_workflows_id_keyspace_idx", to: "keyspace_id", autocommit: true, read_lock: "none"
    add_vindex :pinned_workflows, :pinned_workflows_id_keyspace_idx, :id
  end
end
