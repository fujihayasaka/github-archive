# typed: true

class AddTemplateRepositoryIdToWorkspaces < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Collab)

  def change
    add_column :workspaces, :template_repository_id, :bigint, unsigned: true, null: true
  end
end
