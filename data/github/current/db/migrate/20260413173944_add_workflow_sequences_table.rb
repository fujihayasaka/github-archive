# typed: true
# frozen_string_literal: true

class AddWorkflowSequencesTable < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesActionsChecks)

  def change
    create_table :workflow_sequences, id: :bigint, unsigned: true, charset: "utf8mb4", collation: "utf8mb4_unicode_520_ci" do |t|
      t.column :repository_id, "bigint unsigned", null: false
      t.column :workflow_id, "bigint unsigned", null: false
      t.integer :number, null: false, default: 0
      t.timestamps null: false, precision: 6

      t.index [:repository_id, :workflow_id], unique: true, name: "idx_wf_seq_repository_id_and_workflow_id"
    end

    # Sharding vindex. For tables in `repositories-actions-checks` cluster, use the `repository_id` column.
    add_vindex :workflow_sequences, :hash, :repository_id

    # Auto increment for "workflow_sequences" table. The sequence table needs to exist before this migration is run.
    add_auto_increment :workflow_sequences, :id, :workflow_sequences_id_seq
  end
end
