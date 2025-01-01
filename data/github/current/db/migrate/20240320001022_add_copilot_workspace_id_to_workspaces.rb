class AddCopilotWorkspaceIdToWorkspaces < ActiveRecord::Migration[7.2]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_column :workspaces, :copilot_workspace_id, "varchar(36)", default: nil
  end
end
