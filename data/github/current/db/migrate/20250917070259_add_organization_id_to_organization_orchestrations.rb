# typed: true

class AddOrganizationIdToOrganizationOrchestrations < ActiveRecord::Migration[8.1]
  self.use_connection_class(ApplicationRecord::Domain::Usersd)

  def change
    change_table :organization_orchestrations, bulk: true do |t|
      t.column :organization_id, :bigint, unsigned: true, null: true, after: :parent_id
      t.index :organization_id
      t.index :business_id
    end
  end
end
