# typed: true

class AddIndexToWorkspaces < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    add_index :workspaces, [:deleted_at, :retention_expires_at], name: "index_workspaces_on_deleted_at_and_retention_expires_at"
  end
end
