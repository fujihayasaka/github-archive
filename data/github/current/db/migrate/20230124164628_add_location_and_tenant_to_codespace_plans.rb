# typed: true

class AddLocationAndTenantToCodespacePlans < ActiveRecord::Migration[7.1]
  self.use_connection_class(ApplicationRecord::Domain::Codespaces)

  def up
    change_table :workspace_plans, bulk: true do |t|
      t.change :id, :bigint, unsigned: true, auto_increment: true
      t.change :resource_group_id, :bigint, unsigned: true
    end

    add_column :workspace_plans, :location, :string, null: false, limit: 40, default: ""
    add_column :workspace_plans, :business_id, :bigint, unsigned: true, null: true

    add_index :workspace_plans, [:business_id, :location, :vscs_target], name: "index_workspace_plans_on_business_location_target"
  end

  def down
    change_table :workspace_plans, bulk: true do |t|
      t.change :id, :int, auto_increment: true
      t.change :resource_group_id, :int
    end

    remove_column :workspace_plans, :location
    remove_column :workspace_plans, :business_id

    remove_index :workspace_plans, [:business_id, :location, :vscs_target], name: "index_workspace_plans_on_business_location_target"
  end
end
