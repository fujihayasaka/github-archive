# typed: true

class AddNewColumnsToWorkflowRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflow_runs, bulk: true do |t|
      t.column :tree_id, "varchar(64)", null: true
      t.column :cloned_workflow_run_id, "bigint(20)", unsigned: true, null: true
      t.column :logs_deleted_at, :datetime, null: true, precision: nil
      t.column :workflow_file_checkout_sha, :string, limit: 64, null: true, comment: "Checkout SHA of the workflow file for a required workflow run. For normal workflows, head_sha is the checkout sha of the file and this will be NULL"
      t.remove_index name: "index_workflow_runs_on_repository_id_and_workflow_id"
      t.index [:repository_id, :workflow_id, :event, :tree_id], name: "index_workflow_runs_on_repository_id_workflow_id_event_tree_id"
    end
  end

  def down
    change_table :workflow_runs, bulk: true do |t|
      t.remove :tree_id
      t.remove :cloned_workflow_run_id
      t.remove :logs_deleted_at
      t.remove :workflow_file_checkout_sha
      t.remove_index name: "index_workflow_runs_on_repository_id_workflow_id_event_tree_id"
      t.index [:repository_id, :workflow_id], name: "index_workflow_runs_on_repository_id_and_workflow_id"
    end
  end
end
