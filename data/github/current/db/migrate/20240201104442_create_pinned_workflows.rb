# typed: true
# frozen_string_literal: true
class CreatePinnedWorkflows < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :pinned_workflows, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.bigint :workflow_id, unsigned: true, null: false
      t.bigint :repository_id, unsigned: true, null: false
      t.bigint :pinned_by_id, unsigned: true, null: false

      t.timestamps

      t.index [:repository_id, :workflow_id], unique: true, name: "index_pinned_workflows_on_repository_id_and_workflow_id"
    end

    add_vindex :pinned_workflows, :workflows_id_keyspace_idx, :workflow_id
    add_vindex :pinned_workflows, :hash, :repository_id
    add_auto_increment(:pinned_workflows, :id, :pinned_workflows_id_seq)
  end
end
