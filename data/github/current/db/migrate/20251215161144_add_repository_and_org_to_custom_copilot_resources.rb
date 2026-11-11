# typed: true

class AddRepositoryAndOrgToCustomCopilotResources < ActiveRecord::Migration[8.2]
  self.use_connection_class(ApplicationRecord::Copilot)

  def change
    change_table :custom_copilot_resources, bulk: true do |t|
      t.column :denormalized_repository_id, :bigint, unsigned: true
      t.index :denormalized_repository_id

      t.column :organization_id, :bigint, unsigned: true
      t.index :organization_id
    end
  end
end
