# typed: true
class AddWorkflowRunIdIndexToCodespacePrebuildConfigurations < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_index :codespace_prebuild_configurations, :latest_workflow_run_id, unique: true, name: "index_codespace_prebuild_config_on_workflow_run_id"
  end
end
