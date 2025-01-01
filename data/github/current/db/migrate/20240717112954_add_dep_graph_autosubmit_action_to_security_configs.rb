class AddDepGraphAutosubmitActionToSecurityConfigs < ActiveRecord::Migration[8.0]
  self.use_connection_class(ApplicationRecord::Domain::RepositoriesNotify)

  def change
    change_table(:security_configurations, bulk: true) do |t|
      # Add nullable unsigned integer column for Dependency Graph Autosubmission enablement.
      t.column :dependency_graph_autosubmit_action, :integer, unsigned: true, null: true
      # Add nullable json column for Dependency Graph Autosubmission options values.
      t.column :dependency_graph_autosubmit_action_options, :json, null: true
    end
  end
end
