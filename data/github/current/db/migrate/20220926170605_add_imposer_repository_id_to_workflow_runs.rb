# typed: true
class AddImposerRepositoryIdToWorkflowRuns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflow_runs, bulk: true do |t|
      t.column :imposer_repository_id, :bigint, unsigned: true, null: false, default: 0, comment: "Id of the repository where the required workflow file resides. Will be 0 for non required workflows"
    end
  end

  def down
    change_table :workflow_runs, bulk: true do |t|
      t.remove :imposer_repository_id
    end
  end
end
