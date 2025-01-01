# typed: true
# rubocop:disable GitHub/AvoidRedundantIndex
# Disabled GitHub/AvoidRedundantIndex for now. We will be removing old index in next PR after replacing it with new index in relevant places.
class AddImposerRepositoryIdToWorkflowRunsIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :workflow_runs, bulk: true do |t|
      t.index [:repository_id, :user_hidden, :imposer_repository_id], name: "index_workflow_runs_on_repository_id_user_hidden_imposer_repo_id"
    end
  end

  def down
    change_table :workflow_runs, bulk: true do |t|
      t.remove_index [:repository_id, :user_hidden, :imposer_repository_id], name: "index_workflow_runs_on_repository_id_user_hidden_imposer_repo_id"
    end
  end
end
