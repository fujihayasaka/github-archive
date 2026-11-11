# typed: true

class AddSparkWorkbenchIdIndex < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)
  def change
    add_index :workspaces, [:deleted_at, :spark_workbench_id, :environment_state, :last_used_at], name: "index_workspaces_on_spark_workbench_id_and_state"
  end
end
