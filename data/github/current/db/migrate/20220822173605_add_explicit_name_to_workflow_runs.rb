# typed: true

class AddExplicitNameToWorkflowRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)
  def change
    add_column :workflow_runs, :explicit_name, :boolean, default: false, null: false, comment: "Whether the workflow run was explicitly named"
  end
end
