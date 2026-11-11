# typed: true

class RemoveIndexWorkflowRunsOnRepositoryIdUserHidden < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    remove_index :workflow_runs, name: :index_workflow_runs_on_repository_id_user_hidden, if_exists: true
  end

  def down
    add_index :workflow_runs, [:repository_id, :user_hidden], name: "index_workflow_runs_on_repository_id_user_hidden", if_not_exists: true
  end
end
