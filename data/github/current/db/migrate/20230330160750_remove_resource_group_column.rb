# typed: true
class RemoveResourceGroupColumn < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def change
    remove_column :workspace_plans, :resource_group_id, :bigint, unsigned: true
  end
end
