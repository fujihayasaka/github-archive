class AddWorkflowFileBranchNameToActionsWorkflowRun < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflow_runs, bulk: true do |t|
      t.column :workflow_file_ref, :binary, limit: 1024,  comment: "The branch name as determined by the ref used to select the workflow. Needed for ruleset workflows"
    end
  end

  def down
    change_table :workflow_runs, bulk: true do |t|
      t.remove :workflow_file_ref
    end
  end
end
