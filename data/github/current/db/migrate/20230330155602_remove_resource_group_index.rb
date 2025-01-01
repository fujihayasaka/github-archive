# typed: true
class RemoveResourceGroupIndex < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    remove_index :workspace_plans, column: [:resource_group_id, :name], name: "index_on_resource_group_and_name"
  end
end
