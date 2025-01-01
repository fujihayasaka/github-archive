class ActionsArtifactNewColumns < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::RepositoriesActionsChecks)

  def up
    change_table :artifacts, bulk: true do |t|
      # Change the existing index to start with the repository_id instead of the workflow_run_id, long term will be used for https://github.com/github/c2c-actions-checks/issues/500
      t.index [:repository_id, :workflow_run_id], name: "index_artifacts_on_repository_id_and_workflow_run_id"
      t.remove_index name: "index_artifacts_on_workflow_run_id_and_repository_id"

      # New index so that the list artifacts API doesn't timeout for users with a large amount of artifacts https://github.com/github/killed-query-dashboard-updater/issues/553
      t.index [:repository_id, :id], name: "index_artifacts_on_repository_id_and_id", order: { id: :desc }

      # New columns for v4+ artifact actions taht are tied to jobs/check_runs & have hash metadata
      t.column :check_run_id, :bigint, unsigned: true, null: true
      t.column :upload_hash, "varchar(75)", null: true
    end
  end

  def down
    change_table :artifacts, bulk: true do |t|
      t.index [:workflow_run_id, :repository_id], name: "index_artifacts_on_workflow_run_id_and_repository_id"
      t.remove_index name: "index_artifacts_on_repository_id_and_workflow_run_id"

      t.remove_index name: "index_artifacts_on_repository_id_and_id"

      t.remove :check_run_id
      t.remove :upload_hash
    end
  end
end
