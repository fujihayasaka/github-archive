# typed: true

class AddWorkflowRunIdToArtifacts < ActiveRecord::Migration[7.1]
  # See https://thehub.github.com/engineering/development-and-ops/dotcom/migrations-and-transitions/database-migrations-for-dotcom/
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :artifacts, bulk: true do |t|
      t.column :workflow_run_id, "bigint(20)", unsigned: true, null: true

      t.index [:workflow_run_id, :repository_id], name: "index_artifacts_on_workflow_run_id_and_repository_id"
    end
  end

  def down
    change_table :artifacts, bulk: true do |t|
      t.remove_index [:workflow_run_id, :repository_id], name: "index_artifacts_on_workflow_run_id_and_repository_id"

      t.remove :workflow_run_id
    end
  end
end
