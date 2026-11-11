# typed: true

class AddSparkWorkspaceIdToWorkspaces < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :workspaces, bulk: true do |t|
      t.column :linked_resources, :json, null: true
    end
  end

  def down
    remove_column :workspaces, :linked_resources
  end
end
